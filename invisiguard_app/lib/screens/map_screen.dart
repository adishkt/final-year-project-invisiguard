import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MapScreen – shows live student location from Firebase Realtime Database
// and a geofence circle from Firestore. Long-pressing the map updates the
// geofence centre (live mode only).
// ─────────────────────────────────────────────────────────────────────────────

class MapScreen extends StatefulWidget {
  /// If non-null the map shows this fixed point (history / alert mode).
  final LatLng? initialTarget;

  const MapScreen({super.key, this.initialTarget});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ── Map controller ──────────────────────────────────────────────────────────
  GoogleMapController? _mapController;

  // ── Location state ───────────────────────────────────────────────────────────
  /// Default fallback shown while waiting for a real GPS fix.
  static const LatLng _kDefault = LatLng(10.039298, 76.325);

  LatLng _studentLocation = _kDefault;
  bool _hasRealLocation = false;
  String? _errorMessage;

  // ── Geofence state ───────────────────────────────────────────────────────────
  LatLng _geofenceCenter = const LatLng(10.039298, 76.325);
  double _geofenceRadius = 300; // metres
  bool _isInsideGeofence = true;

  // ── Firebase subscriptions ───────────────────────────────────────────────────
  StreamSubscription<DatabaseEvent>? _locationSub;
  StreamSubscription<DocumentSnapshot>? _geofenceSub;
  StreamSubscription<DocumentSnapshot>? _settingsSub;

  // ─────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    if (widget.initialTarget != null) {
      // ── History / alert mode: fixed pin, no live updates ───────────────────
      _studentLocation = widget.initialTarget!;
      _hasRealLocation = true;
    } else {
      // ── Live mode: stream location from RTDB ───────────────────────────────
      _startLocationStream();
    }

    // Always listen for geofence changes so the safe-zone ring is drawn.
    _startGeofenceStreams();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _geofenceSub?.cancel();
    _settingsSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Firebase Realtime Database – live location
  // ─────────────────────────────────────────────────────────────────────────────

  void _startLocationStream() {
    final DatabaseReference ref = FirebaseDatabase.instance.ref('student');

    _locationSub = ref.onValue.listen(
      (DatabaseEvent event) {
        if (!mounted) return;

        final raw = event.snapshot.value;
        if (raw == null) {
          debugPrint('[MapScreen] RTDB snapshot is null – no data yet');
          return;
        }

        // Accept both Map<Object?, Object?> (RTDB default) and Map<String, dynamic>
        final Map<String, dynamic> data = Map<String, dynamic>.from(raw as Map);

        // Try both common key conventions: "latitude" / "lat", "longitude" / "lng"
        double? lat = _toDouble(data['latitude'] ?? data['lat']);
        double? lng = _toDouble(data['longitude'] ?? data['lng']);

        if (lat == null || lng == null) {
          debugPrint('[MapScreen] RTDB data missing lat/lng: $data');
          return;
        }

        if (lat == 0 || lng == 0) {
          debugPrint('[MapScreen] RTDB data is 0,0 - waiting for GPS fix');
          return;
        }

        final LatLng newPos = LatLng(lat, lng);

        setState(() {
          _studentLocation = newPos;
          _hasRealLocation = true;
          _errorMessage = null;
        });

        // Move camera smoothly to the new position.
        _animateCameraTo(newPos);

        // Re-evaluate geofence breach.
        _checkGeofence();
      },
      onError: (Object error) {
        debugPrint('[MapScreen] RTDB error: $error');
        if (mounted) {
          setState(() => _errorMessage = 'Location stream error: $error');
        }
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Firestore – geofence centre + radius settings
  // ─────────────────────────────────────────────────────────────────────────────

  void _startGeofenceStreams() {
    final String uid = FirebaseAuth.instance.currentUser!.uid;

    // Geofence centre document
    _geofenceSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('geofence')
        .doc('current')
        .snapshots()
        .listen((DocumentSnapshot doc) {
          if (!doc.exists || !mounted) return;
          final d = doc.data() as Map<String, dynamic>?;
          if (d == null) return;
          final lat = _toDouble(d['latitude']);
          final lng = _toDouble(d['longitude']);
          if (lat == null || lng == null) return;
          setState(() => _geofenceCenter = LatLng(lat, lng));
          _checkGeofence();
        });

    // Geofence radius stored in the user settings document
    _settingsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((DocumentSnapshot doc) {
          if (!doc.exists || !mounted) return;
          final d = doc.data() as Map<String, dynamic>?;
          final settings = d?['settings'] as Map<String, dynamic>?;
          if (settings == null) return;
          final newRadius = _toDouble(settings['geofenceRadius']) ?? 300;
          if (newRadius != _geofenceRadius) {
            setState(() => _geofenceRadius = newRadius);
            _checkGeofence();
          }
        });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Geofence helpers
  // ─────────────────────────────────────────────────────────────────────────────

  void _checkGeofence() {
    if (widget.initialTarget != null) return; // history mode – skip alerts
    final dist = _haversineDistance(_studentLocation, _geofenceCenter);
    final nowInside = dist <= _geofenceRadius;
    if (nowInside == _isInsideGeofence) return;
    setState(() => _isInsideGeofence = nowInside);
    _writeGeofenceStatus(nowInside);
    if (!nowInside) _writeGeofenceExitAlert();
  }

  Future<void> _writeGeofenceStatus(bool inside) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('status')
        .doc('current')
        .set({'insideGeofence': inside, 'updatedAt': Timestamp.now()});
  }

  Future<void> _writeGeofenceExitAlert() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('alerts')
        .add({
          'type': 'GEOFENCE_EXIT',
          'message': 'Student exited the safe zone',
          'confidence': 0.92,
          'latitude': _studentLocation.latitude,
          'longitude': _studentLocation.longitude,
          'createdAt': Timestamp.now(),
        });
  }

  Future<void> _saveGeofenceCenter(LatLng center) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('geofence')
        .doc('current')
        .set({
          'latitude': center.latitude,
          'longitude': center.longitude,
          'updatedAt': Timestamp.now(),
        }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Safe zone centre updated')));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Camera helpers
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _animateCameraTo(LatLng target) async {
    await _mapController?.animateCamera(CameraUpdate.newLatLng(target));
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Set<Circle> circles = {
      Circle(
        circleId: const CircleId('safe_zone'),
        center: _geofenceCenter,
        radius: _geofenceRadius,
        fillColor: Colors.blue.withValues(alpha: 0.12),
        strokeColor: Colors.blueAccent,
        strokeWidth: 2,
      ),
    };

    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId('student'),
        position: _studentLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _hasRealLocation
              ? BitmapDescriptor.hueRed
              : BitmapDescriptor.hueAzure,
        ),
        infoWindow: InfoWindow(
          title: _hasRealLocation ? 'Student Location' : 'Waiting for GPS…',
          snippet: _hasRealLocation
              ? '${_studentLocation.latitude.toStringAsFixed(5)}, '
                    '${_studentLocation.longitude.toStringAsFixed(5)}'
              : null,
        ),
      ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Location'),
        actions: [_buildStatusChip()],
      ),
      body: Stack(
        children: [
          // ── Google Map ─────────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _studentLocation,
              zoom: 16,
            ),
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              // Animate to location right after map is ready
              Future.microtask(() => _animateCameraTo(_studentLocation));
            },
            onLongPress: widget.initialTarget == null
                ? _saveGeofenceCenter
                : null,
            markers: markers,
            circles: circles,
            zoomControlsEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
          ),

          // ── Loading banner ─────────────────────────────────────────────────
          if (!_hasRealLocation) _buildLoadingBanner(),

          // ── Error banner ───────────────────────────────────────────────────
          if (_errorMessage != null) _buildErrorBanner(),

          // ── Geofence breach badge ──────────────────────────────────────────
          if (_hasRealLocation &&
              !_isInsideGeofence &&
              widget.initialTarget == null)
            _buildBreachBadge(),

          // ── Bottom action bar (live mode only) ─────────────────────────────
          if (widget.initialTarget == null) _buildBottomBar(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Sub-widgets
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildStatusChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _hasRealLocation ? Colors.greenAccent : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _hasRealLocation ? 'Live' : 'Waiting…',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBanner() {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: _floatingCard(
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Getting student location…', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildBreachBadge() {
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.orange.shade700,
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Student is outside the safe zone!',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _floatingCard(
            child: const Text(
              'Long-press the map to move the safe zone',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.my_location),
              label: const Text('Centre on Student'),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _animateCameraTo(_studentLocation),
            ),
          ),
        ],
      ),
    );
  }

  /// Generic floating card widget.
  Widget _floatingCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: child,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Utilities
  // ─────────────────────────────────────────────────────────────────────────────

  /// Safely coerce a value to double (handles int, double, String).
  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Haversine great-circle distance in metres.
  static double _haversineDistance(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) *
            cos(_rad(b.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  static double _rad(double deg) => deg * (pi / 180);
}
