#!/usr/bin/env python3
"""
2D Heat Equation Solver with MPI Domain Decomposition
Solves: ∂u/∂t = α(∂²u/∂x² + ∂²u/∂y²)
"""

from mpi4py import MPI
import numpy as np
import sys
import argparse

def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='2D Heat Equation Solver with MPI')
    parser.add_argument('--nx', type=int, default=1024, help='Grid size in x direction')
    parser.add_argument('--ny', type=int, default=1024, help='Grid size in y direction')
    parser.add_argument('--steps', type=int, default=1000, help='Number of time steps')
    parser.add_argument('--alpha', type=float, default=0.01, help='Thermal diffusivity')
    return parser.parse_args()

def main():
    # Parse arguments
    args = parse_args()
    
    # MPI setup
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()
    
    # Global problem parameters
    nx_global = args.nx
    ny_global = args.ny
    num_steps = args.steps
    alpha = args.alpha
    dx = 1.0 / (nx_global - 1)
    dy = 1.0 / (ny_global - 1)
    dt = 0.25 * min(dx, dy)**2 / alpha
    
    if rank == 0:
        print("\nHeat Solver - Working Version")
        print(f"Global grid: {nx_global} x {ny_global}")
        print(f"Processes: {size}")
    
    # Domain decomposition (split along x-axis)
    nx_local = nx_global // size
    remainder = nx_global % size
    
    # Distribute remainder rows
    if rank < remainder:
        nx_local += 1
        start_row = rank * nx_local
    else:
        start_row = remainder * (nx_local + 1) + (rank - remainder) * nx_local
    
    ny_local = ny_global
    
    if rank == 0:
        print(f"Local grid: ~{nx_local} x {ny_local}")
        print("-" * 40)
    
    # Allocate local arrays with ghost cells
    u = np.zeros((nx_local + 2, ny_local))
    u_new = np.zeros((nx_local + 2, ny_local))
    
    # Initial condition: hot center
    center_x = nx_global // 2
    center_y = ny_global // 2
    radius = min(nx_global, ny_global) // 10
    
    for i in range(nx_local):
        global_i = start_row + i
        for j in range(ny_local):
            dist = np.sqrt((global_i - center_x)**2 + (j - center_y)**2)
            if dist < radius:
                u[i+1, j] = 100.0
    
    # Time stepping
    import time
    start_time = time.time()
    
    progress_interval = num_steps // 10
    
    for step in range(num_steps):
        # Exchange ghost cells
        if rank > 0:
            comm.Send(u[1, :], dest=rank-1, tag=1)
            comm.Recv(u[0, :], source=rank-1, tag=2)
        
        if rank < size - 1:
            comm.Send(u[nx_local, :], dest=rank+1, tag=2)
            comm.Recv(u[nx_local+1, :], source=rank+1, tag=1)
        
        # Update interior points
        for i in range(1, nx_local + 1):
            for j in range(1, ny_local - 1):
                laplacian = (u[i+1, j] + u[i-1, j] - 2*u[i, j]) / dx**2 + \
                           (u[i, j+1] + u[i, j-1] - 2*u[i, j]) / dy**2
                u_new[i, j] = u[i, j] + dt * alpha * laplacian
        
        # Boundary conditions (fixed at 0)
        u_new[1:nx_local+1, 0] = 0.0
        u_new[1:nx_local+1, ny_local-1] = 0.0
        
        # Swap arrays
        u, u_new = u_new, u
        
        # Progress reporting
        if rank == 0 and (step + 1) % progress_interval == 0:
            progress = ((step + 1) / num_steps) * 100
            print(f"Progress: {progress:.0f}%")
    
    end_time = time.time()
    elapsed_time = end_time - start_time
    
    # Gather center temperature
    center_local_i = center_x - start_row
    center_temp = None
    
    if start_row <= center_x < start_row + nx_local:
        center_temp = u[center_local_i + 1, center_y]
    
    all_center_temps = comm.gather(center_temp, root=0)
    
    if rank == 0:
        center_temperature = [t for t in all_center_temps if t is not None][0]
        
        total_cells = nx_global * ny_global
        total_updates = total_cells * num_steps
        updates_per_sec = total_updates / elapsed_time
        time_per_step = (elapsed_time / num_steps) * 1000  # ms
        
        print("=" * 50)
        print("Performance Summary")
        print("=" * 50)
        print(f"Grid size: {nx_global} x {ny_global}")
        print(f"Processes: {size}")
        print(f"Time steps: {num_steps}")
        print(f"Total time: {elapsed_time:.3f} seconds")
        print(f"Updates/sec: {updates_per_sec:.2e}")
        print(f"Time per step: {time_per_step:.3f} ms")
        print(f"Center temperature: {center_temperature:.2f}°C")
        print("=" * 50)

if __name__ == "__main__":
    main()
