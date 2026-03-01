"""
firebase_inference.py
=====================
Real-time inference service for InvisGuard.

Reads accelerometer (Acc_x, Acc_y, Acc_z) data pushed by a device to
Firebase Realtime Database, runs it through:
  1. FallDetectionLSTM    → detects falls
  2. MotionClassifierLSTM → detects sudden motion

Writes combined predictions back to Firebase.

Firebase DB schema
------------------
INPUT  (device writes):
  /devices/{DEVICE_ID}/sensor_data/latest
    Acc_x     : float
    Acc_y     : float
    Acc_z     : float
    timestamp : int  (Unix ms)

OUTPUT (this service writes):
  /devices/{DEVICE_ID}/predictions/
    fall_detection/
      probability : float
      prediction  : "FALL" | "NO-FALL"
      updated_at  : int
    motion_classifier/
      probability : float
      prediction  : "SUDDEN" | "NORMAL"
      updated_at  : int
    alert         : bool   (true if any model triggers)
    buffer_size   : int    (current sample buffer length)

Usage
-----
  # Normal mode (connects to Firebase):
  python firebase_inference.py

  # Test mode (replays a local CSV, no Firebase needed):
  python firebase_inference.py --test-mode --csv JO_FALL/volunteer_6_left_hand/adl/applaud.csv
"""

import argparse
import os
import sys
import time
import threading
from collections import deque
from typing import Optional
import datetime

import numpy as np
import torch

# ─────────────────────────────────────────────────────
#  ██████╗  ██████╗ ███╗   ██╗███████╗██╗ ██████╗
#  ██╔════╝██╔═══██╗████╗  ██║██╔════╝██║██╔════╝
#  ██║     ██║   ██║██╔██╗ ██║█████╗  ██║██║  ███╗
#  ██║     ██║   ██║██║╚██╗██║██╔══╝  ██║██║   ██║
#  ╚██████╗╚██████╔╝██║ ╚████║██║     ██║╚██████╔╝
#   ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝     ╚═╝ ╚═════╝
# ─────────────────────────────────────────────────────
#  Edit these to match your setup
# ─────────────────────────────────────────────────────

FIREBASE_CRED_PATH  = "serviceAccountKey.json"   # Downloaded from Firebase Console
FIREBASE_DB_URL     = "https://internetot-default-rtdb.firebaseio.com"  # Your DB URL
SENSOR_NODE         = "student"                  # Root node in Firebase (e.g. "student")

# Field names in your Firebase node
FIELD_X             = "accelX"
FIELD_Y             = "accelY"
FIELD_Z             = "accelZ"
FIELD_TIMESTAMP     = "timestamp"

FALL_CKPT_PATH      = "checkpoints/fall-detection-epoch=35-val_loss=0.26.ckpt"
MOTION_CKPT_PATH    = "checkpoints/motion/motion-classifier-epoch=14-val_loss=0.00.ckpt"

SEQ_LEN             = 100    # Number of samples needed before inference
STEP_SIZE           = 6     # Run inference on EVERY new reading (fall can happen in one moment)
THRESHOLD_FALL      = 0.5   # Increased to reduce false positives (was 0.5)
THRESHOLD_MOTION    = 0.5   # Sudden motion probability threshold
POLL_INTERVAL_SEC   = 0.5    # How often to poll Firebase (seconds)

# ─────────────────────────────────────────────────────




# ── Model imports ────────────────────────────────────
from train_fall import FallDetectionLSTM
from detect_motion_ml import MotionClassifierLSTM, MotionFeatureExtractor
from create_dataset import normalize_sequences_per_feature


def _normalize_ml(sequences: np.ndarray) -> np.ndarray:
    """Min-max normalize per feature (matches predict_single_file_ml.py)."""
    n_windows, seq_len, n_features = sequences.shape
    flat = sequences.reshape(-1, n_features)
    for f in range(n_features):
        col = flat[:, f]
        mn, mx = col.min(), col.max()
        flat[:, f] = (col - mn) / (mx - mn) if mx - mn > 1e-8 else 0.0
    return flat.reshape(n_windows, seq_len, n_features)


# ── Model loader ─────────────────────────────────────
class ModelBundle:
    """Loads and holds both models. Thread-safe for inference."""

    def __init__(self, fall_ckpt: str, motion_ckpt: str):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        print(f"[ModelBundle] Using device: {self.device}")

        print(f"[ModelBundle] Loading FallDetectionLSTM from {fall_ckpt}")
        self.fall_model = FallDetectionLSTM.load_from_checkpoint(
            fall_ckpt, map_location=self.device
        )
        self.fall_model.to(self.device)
        self.fall_model.eval()

        print(f"[ModelBundle] Loading MotionClassifierLSTM from {motion_ckpt}")
        self.motion_model = MotionClassifierLSTM.load_from_checkpoint(
            motion_ckpt, map_location=self.device
        )
        self.motion_model.to(self.device)
        self.motion_model.eval()

        print("[ModelBundle] Both models loaded successfully [OK]")

    @torch.no_grad()
    def predict(self, window: np.ndarray):
        """
        Run both models on a single window.

        Parameters
        ----------
        window : np.ndarray, shape (SEQ_LEN, 3)  [x, y, z]

        Returns
        -------
        fall_prob   : float
        motion_prob : float
        """
        # 1. Apply GLOBAL Z-score normalization (from JO_FALL dataset)
        # instead of local per-window normalizaton which magnifies sensor noise
        means = np.array([0.3491856, -0.1723468, 0.3566128], dtype=np.float32)
        stds = np.array([0.3911440, 0.6869545, 0.4376679], dtype=np.float32)
        
        raw_seq = window[np.newaxis, :, :].astype(np.float32)  # (1, SEQ_LEN, 3)
        norm_seq = (raw_seq - means) / stds

        # ── Fall detection ───────────────────────────
        fall_tensor = torch.from_numpy(norm_seq).float().to(self.device)
        fall_logit = self.fall_model(fall_tensor)
        fall_prob = float(torch.sigmoid(fall_logit).cpu().numpy().flatten()[0])

        # ── Motion classification ────────────────────
        # Skip the ML motion model which hallucinates on perfectly still data.
        # Compute actual physical motion variance (std dev) to detect active movement.
        x, y, z = window[:, 0], window[:, 1], window[:, 2]
        magnitude = np.sqrt(x**2 + y**2 + z**2)
        
        std_mag = float(np.std(magnitude))
        # Map variance to a 0.0 - 1.0 probability. 
        # std < 0.01g = 0%, std > 0.05g = 100%
        mot_prob = float(np.clip((std_mag - 0.01) / 0.04, 0.0, 1.0))

        return fall_prob, mot_prob


# ── Rolling buffer ───────────────────────────────────
class SampleBuffer:
    """Thread-safe rolling window of (x, y, z) samples."""

    def __init__(self, maxlen: int, step_size: int):
        self._buf: deque = deque(maxlen=maxlen)
        self._lock = threading.Lock()
        self._samples_since_infer = 0
        self._step_size = step_size
        self._seeded = False

    def preseed(self, x: float, y: float, z: float):
        """Fill the entire buffer with a single reading so inference starts immediately."""
        with self._lock:
            if not self._seeded:
                for _ in range(self._buf.maxlen):
                    self._buf.append([x, y, z])
                self._seeded = True
                print(f"[Buffer] Pre-seeded with first reading: x={x:.2f} y={y:.2f} z={z:.2f} — inference ready!")

    def add(self, x: float, y: float, z: float) -> bool:
        """Add a sample. Returns True when a new inference should be run."""
        with self._lock:
            self._buf.append([x, y, z])
            self._samples_since_infer += 1
            if len(self._buf) >= self._buf.maxlen and self._samples_since_infer >= self._step_size:
                self._samples_since_infer = 0
                return True
        return False

    def get_window(self) -> Optional[np.ndarray]:
        """Return the current window as numpy array (SEQ_LEN, 3) or None."""
        with self._lock:
            if len(self._buf) < self._buf.maxlen:
                return None
            return np.array(list(self._buf), dtype=np.float32)

    def __len__(self):
        with self._lock:
            return len(self._buf)


# ── Firebase helpers ─────────────────────────────────
def init_firebase(cred_path: str, db_url: str):
    """Initialize Firebase Admin SDK. Returns the db reference."""
    import firebase_admin
    from firebase_admin import credentials, db

    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred, {"databaseURL": db_url})
        print("[Firebase] Connected [OK]")
    return db


def get_latest_reading(db) -> Optional[dict]:
    """Fetch the latest sensor reading from Firebase /student node."""
    ref = db.reference(f"/{SENSOR_NODE}")
    return ref.get()


def write_predictions(db, fall_prob: float, mot_prob: float,
                      is_confirmed_fall: bool, has_motion: bool, buf_size: int):
    """Write ML prediction results back into the Firebase /student node."""
    now_ms = int(time.time() * 1000)
    ref = db.reference(f"/{SENSOR_NODE}")
    alert = is_confirmed_fall

    update_data = {
        "ml_fall_probability":  round(fall_prob, 4),
        "ml_fall_prediction":   "FALL" if is_confirmed_fall else "NO-FALL",
        "ml_motion_probability": round(mot_prob, 4),
        "ml_motion_prediction":  "MOTION" if has_motion else "NO-MOTION",
        "ml_alert":             alert,
        "ml_buffer_size":       buf_size,
        "ml_updated_at":        now_ms,
    }
    
    # If it's a confirmed fall, write an overriding alert field so the mobile app gets a fresh trigger
    if alert:
        update_data["is_alert"] = True
        update_data["alert_reason"] = "fall_detected"

    ref.update(update_data)


# ── Real-time listener (push-based) ─────────────────
class FirebaseListener:
    """
    Listens to Firebase using on_value callback (push-based).
    More efficient than polling.
    """

    def __init__(self, db, buffer: SampleBuffer,
                 models: ModelBundle, threshold_fall: float, threshold_motion: float):
        self._db = db
        self._buffer = buffer
        self._models = models
        self._threshold_fall = threshold_fall
        self._threshold_motion = threshold_motion
        self._last_ts = None
        self._motion_cooldown = 0

    def start(self):
        from firebase_admin import db as fb_db
        ref = fb_db.reference(f"/{SENSOR_NODE}")
        ref.listen(self._on_new_data)
        print(f"[FirebaseListener] Listening to /{SENSOR_NODE}")
        # Keep main thread alive
        while True:
            time.sleep(1)

    def _on_new_data(self, event):
        data = event.data
        if not data:
            return
        ts = data.get(FIELD_TIMESTAMP, 0)
        if ts == self._last_ts:
            return  # duplicate event
        self._last_ts = ts

        try:
            x = float(data[FIELD_X]) / 9.81
            y = float(data[FIELD_Y]) / 9.81
            z = float(data[FIELD_Z]) / 9.81
        except (KeyError, ValueError, TypeError) as e:
            print(f"[Listener] Bad data: {e} — {data}")
            return

        should_infer = self._buffer.add(x, y, z)
        if should_infer:
            window = self._buffer.get_window()
            if window is not None:
                self._run_inference(window)

    def _run_inference(self, window: np.ndarray):
        try:
            fall_prob, mot_prob = self._models.predict(window)
            now = datetime.datetime.now().strftime("%H:%M:%S")
            is_fall_raw = fall_prob >= self._threshold_fall
            has_motion = mot_prob >= self._threshold_motion
            
            if has_motion:
                self._motion_cooldown = 15  # Remember recent motion for 15 frames (~7 seconds)
            else:
                if self._motion_cooldown > 0:
                    self._motion_cooldown -= 1
                    
            # Trigger fall alert if there is a fall AND (sudden motion OR no motion)
            # Normal motion means has_motion is False AND we haven't seen sudden motion recently
            is_confirmed_fall = is_fall_raw and (has_motion or self._motion_cooldown == 0)
            alert = is_confirmed_fall
            print(
                f"[{now}] Buffer:{len(self._buffer)} | "
                f"Fall={fall_prob:.3f}({'[FALL]' if is_confirmed_fall else 'ok'}) | "
                f"Motion={mot_prob:.3f}({'[MOTION]' if has_motion else 'NO-MOTION'}) | "
                f"{'[ALERT]' if alert else '[safe]'}"
            )
            write_predictions(
                self._db,
                fall_prob, mot_prob,
                is_confirmed_fall, has_motion,
                len(self._buffer),
            )
        except Exception as e:
            print(f"[Inference] Error: {e}")


# ── Polling fallback ─────────────────────────────────
class FirebasePoller:
    """
    Polls Firebase every POLL_INTERVAL_SEC seconds.
    Detects new data by checking BOTH timestamp AND actual value changes,
    so it works even if the device sends a constant/slow timestamp.
    """

    def __init__(self, db, buffer: SampleBuffer,
                 models: ModelBundle, threshold_fall: float, threshold_motion: float,
                 poll_interval: float = 0.3):
        self._db = db
        self._buffer = buffer
        self._models = models
        self._threshold_fall = threshold_fall
        self._threshold_motion = threshold_motion
        self._poll_interval = poll_interval
        self._last_ts = None
        self._last_xyz = None  # track value changes independently
        self._progress_printed = -1
        self._motion_cooldown = 0

    def _is_new_reading(self, data: dict) -> bool:
        """Return True if the data represents a new reading we haven't processed."""
        ts  = data.get(FIELD_TIMESTAMP, 0)
        x   = data.get(FIELD_X, None)
        y   = data.get(FIELD_Y, None)
        z   = data.get(FIELD_Z, None)

        if x is None or y is None or z is None:
            return False

        xyz = (round(float(x), 4), round(float(y), 4), round(float(z), 4))

        # Accept if timestamp changed OR if the xyz values changed
        ts_new  = (ts != self._last_ts)
        xyz_new = (xyz != self._last_xyz)

        if ts_new or xyz_new:
            self._last_ts  = ts
            self._last_xyz = xyz
            return True
        return False

    def run(self):
        print(f"[Poller] Polling /{SENSOR_NODE} every {self._poll_interval}s")
        print(f"[Poller] Waiting for first reading to pre-seed buffer...")
        while True:
            try:
                data = get_latest_reading(self._db)
                if data and self._is_new_reading(data):
                    x = float(data.get(FIELD_X, 0)) / 9.81
                    y = float(data.get(FIELD_Y, 0)) / 9.81
                    z = float(data.get(FIELD_Z, 0)) / 9.81

                    # Pre-seed so inference runs immediately on restart
                    self._buffer.preseed(x, y, z)

                    should_infer = self._buffer.add(x, y, z)

                    if should_infer:
                        window = self._buffer.get_window()
                        if window is not None:
                            self._infer_and_write(window)

            except Exception as e:
                print(f"[Poller] Error: {e}")
            time.sleep(self._poll_interval)

    def _infer_and_write(self, window: np.ndarray):
        try:
            fall_prob, mot_prob = self._models.predict(window)
            now = datetime.datetime.now().strftime("%H:%M:%S")
            is_fall_raw = fall_prob >= self._threshold_fall
            has_motion = mot_prob >= self._threshold_motion

            if has_motion:
                self._motion_cooldown = 15  # Remember recent motion for 15 frames (~7 seconds)
            else:
                if self._motion_cooldown > 0:
                    self._motion_cooldown -= 1

            # Trigger fall alert if there is a fall AND (sudden motion OR no motion)
            # Normal motion means has_motion is False AND we haven't seen sudden motion recently
            is_confirmed_fall = is_fall_raw and (has_motion or self._motion_cooldown == 0)
            alert = is_confirmed_fall
            print(
                f"[{now}] Buffer:{len(self._buffer)} | "
                f"Fall={fall_prob:.3f}({'[FALL]' if is_confirmed_fall else 'ok'}) | "
                f"Motion={mot_prob:.3f}({'[MOTION]' if has_motion else 'NO-MOTION'}) | "
                f"{'*** ALERT ***' if alert else '[safe]'}"
            )
            write_predictions(
                self._db,
                fall_prob, mot_prob,
                is_confirmed_fall, has_motion,
                len(self._buffer),
            )
        except Exception as e:
            print(f"[Inference] Error: {e}")


# ── Test mode (no Firebase needed) ──────────────────
def run_test_mode(csv_path: str, fall_ckpt: str, motion_ckpt: str):
    """Replay a CSV file sample-by-sample to test the pipeline locally."""
    import pandas as pd
    print("=" * 60)
    print("TEST MODE — replaying CSV (no Firebase connection)")
    print(f"CSV:          {csv_path}")
    print(f"Fall ckpt:    {fall_ckpt}")
    print(f"Motion ckpt:  {motion_ckpt}")
    print("=" * 60)

    df = pd.read_csv(csv_path)
    # Auto-detect x,y,z columns (tries device field names first)
    for needed in ([FIELD_X, FIELD_Y, FIELD_Z], ["Acc_x", "Acc_y", "Acc_z"], ["x", "y", "z"]):
        if all(c in df.columns for c in needed):
            cols = needed
            break
    else:
        numeric = df.select_dtypes(include=[np.number]).columns.tolist()
        if len(numeric) < 3:
            sys.exit("ERROR: CSV needs at least 3 numeric columns for x,y,z")
        cols = numeric[:3]
    print(f"Using columns: {cols}")

    models = ModelBundle(fall_ckpt, motion_ckpt)
    buffer = SampleBuffer(maxlen=SEQ_LEN, step_size=STEP_SIZE)

    inference_count = 0
    motion_cooldown = 0
    for idx, row in df.iterrows():
        x, y, z = float(row[cols[0]]), float(row[cols[1]]), float(row[cols[2]])
        should_infer = buffer.add(x, y, z)

        if should_infer:
            window = buffer.get_window()
            if window is not None:
                fall_prob, mot_prob = models.predict(window)
                is_fall_raw = fall_prob >= THRESHOLD_FALL
                has_motion = mot_prob >= THRESHOLD_MOTION
                
                if has_motion:
                    motion_cooldown = 15
                else:
                    if motion_cooldown > 0:
                        motion_cooldown -= 1
                        
                # Trigger fall alert if there is a fall AND (sudden motion OR no motion)
                # Normal motion means has_motion is False AND we haven't seen sudden motion recently
                is_confirmed_fall = is_fall_raw and (has_motion or motion_cooldown == 0)
                alert = is_confirmed_fall
                inference_count += 1
                print(
                    f"  Window #{inference_count:03d} @ sample {idx:04d} | "
                    f"Fall={fall_prob:.3f} ({'FALL' if is_confirmed_fall else 'NO-FALL'}) | "
                    f"Motion={mot_prob:.3f} ({'MOTION' if has_motion else 'NO-MOTION'}) | "
                    f"{'[ALERT]' if alert else '[safe]'}"
                )

    print(f"\nTest mode complete. Total inferences: {inference_count}")


# ── Entry point ──────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="InvisGuard Firebase Inference Service")
    parser.add_argument("--test-mode", action="store_true",
                        help="Replay a local CSV instead of connecting to Firebase")
    parser.add_argument("--csv", type=str,
                        default=r"JO_FALL/volunteer_6_left_hand/adl/applaud.csv",
                        help="CSV path for --test-mode")
    parser.add_argument("--poll", action="store_true",
                        help="Use polling instead of real-time listener")
    parser.add_argument("--fall-ckpt", type=str, default=FALL_CKPT_PATH)
    parser.add_argument("--motion-ckpt", type=str, default=MOTION_CKPT_PATH)
    args = parser.parse_args()

    # ── Validate checkpoints ─────────────────────────
    for ckpt_name, ckpt_path in [("Fall", args.fall_ckpt), ("Motion", args.motion_ckpt)]:
        if not os.path.exists(ckpt_path):
            print(f"ERROR: {ckpt_name} checkpoint not found: {ckpt_path}")
            sys.exit(1)

    # ── Test mode ────────────────────────────────────
    if args.test_mode:
        run_test_mode(args.csv, args.fall_ckpt, args.motion_ckpt)
        return

    # ── Firebase mode ────────────────────────────────
    if not os.path.exists(FIREBASE_CRED_PATH):
        print(f"ERROR: Firebase credentials not found at '{FIREBASE_CRED_PATH}'")
        print("  → Download serviceAccountKey.json from Firebase Console")
        print("    Project Settings → Service Accounts → Generate new private key")
        sys.exit(1)

    if "YOUR-PROJECT" in FIREBASE_DB_URL:
        print("ERROR: Please set FIREBASE_DB_URL at the top of firebase_inference.py")
        sys.exit(1)

    print("=" * 60)
    print("InvisGuard Firebase Inference Service")
    print(f"  Node:         /{SENSOR_NODE}")
    print(f"  Fields:       {FIELD_X}, {FIELD_Y}, {FIELD_Z}")
    print(f"  DB URL:       {FIREBASE_DB_URL}")
    print(f"  Fall ckpt:    {args.fall_ckpt}")
    print(f"  Motion ckpt:  {args.motion_ckpt}")
    print(f"  Seq len:      {SEQ_LEN}  |  Step: {STEP_SIZE}")
    print(f"  Mode:         {'Polling' if args.poll else 'Real-time listener'}")
    print("=" * 60)

    db = init_firebase(FIREBASE_CRED_PATH, FIREBASE_DB_URL)
    models = ModelBundle(args.fall_ckpt, args.motion_ckpt)
    buffer = SampleBuffer(maxlen=SEQ_LEN, step_size=STEP_SIZE)

    # Always use polling — the WebSocket listener crashes on Windows
    poller = FirebasePoller(
        db=db,
        buffer=buffer,
        models=models,
        threshold_fall=THRESHOLD_FALL,
        threshold_motion=THRESHOLD_MOTION,
        poll_interval=POLL_INTERVAL_SEC,
    )
    poller.run()


if __name__ == "__main__":
    main()
