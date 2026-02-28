import os
import numpy as np
import pandas as pd

def generate_static_data(out_dir, num_files=200, rows_per_file=200):
    os.makedirs(out_dir, exist_ok=True)
    
    # We want to simulate the device resting in various orientations
    # With a small amount of sensor noise
    
    for i in range(num_files):
        # Generate random static orientation (nx, ny, nz) with magnitude ~ 1.0g
        vec = np.random.randn(3)
        vec /= np.linalg.norm(vec)
        
        x_base, y_base, z_base = vec
        
        # Add random noise (~ 0.005g)
        x_noise = np.random.normal(0, 0.005, rows_per_file)
        y_noise = np.random.normal(0, 0.005, rows_per_file)
        z_noise = np.random.normal(0, 0.005, rows_per_file)
        
        df = pd.DataFrame({
            'x': x_base + x_noise,
            'y': y_base + y_noise,
            'z': z_base + z_noise
        })
        
        df.to_csv(os.path.join(out_dir, f"static_{i:03d}.csv"), index=False)
        
    print(f"Generated {num_files} static CSV files in {out_dir}")

if __name__ == "__main__":
    out_dir = "JO_FALL/synthetic_static/adl"
    generate_static_data(out_dir)
