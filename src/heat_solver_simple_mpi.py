#!/usr/bin/env python3
"""
Simplified MPI heat solver for testing
"""
from mpi4py import MPI
import numpy as np
import time

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

# Simple parameters
nx, ny = 256, 256
steps = 100
ALPHA = 0.01

# Initialize local grid (no domain decomposition for now)
u = np.full((nx, ny), 20.0)
u[0, :] = 100.0  # Top hot
u[-1, :] = 0.0   # Bottom cold

# Time step
dx = dy = 1.0 / (nx - 1)
dt = 0.25 * min(dx**2, dy**2) / ALPHA
rx = ALPHA * dt / dx**2
ry = ALPHA * dt / dy**2

start_time = MPI.Wtime()

# Simple time stepping (each process does full grid - not efficient but works)
for step in range(steps):
    u_new = u.copy()
    
    # Apply stencil
    u_new[1:-1, 1:-1] = (
        u[1:-1, 1:-1] + 
        rx * (u[:-2, 1:-1] - 2*u[1:-1, 1:-1] + u[2:, 1:-1]) +
        ry * (u[1:-1, :-2] - 2*u[1:-1, 1:-1] + u[1:-1, 2:])
    )
    
    # Keep boundaries
    u_new[0, :] = 100.0
    u_new[-1, :] = 0.0
    u_new[:, 0] = 0.0
    u_new[:, -1] = 0.0
    
    u = u_new
    
    # Progress report from rank 0
    if rank == 0 and (step + 1) % 20 == 0:
        print(f"Step {step + 1}/{steps}")

# All processes synchronize
comm.Barrier()
end_time = MPI.Wtime()

if rank == 0:
    elapsed = end_time - start_time
    print(f"\nCompleted in {elapsed:.2f} seconds")
    print(f"Center temperature: {u[nx//2, ny//2]:.2f}°C")
    print(f"All {size} processes finished successfully!")
