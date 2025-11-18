#!/usr/bin/env python3
"""
MPI-based Heat Equation Solver in Python
Domain decomposition with ghost cell exchange
"""
import numpy as np
from mpi4py import MPI
import time
import sys
import os
from dataclasses import dataclass
from typing import Tuple, Optional

# Check if user root or not
if os.getuid() == 0:
    print("\n"+"-"*60 )
    print("ERROR: Don't run GPU as root! Use: su - ansible")
    print("-"*60 + "\n")
    sys.exit(1)

# Physical parameters
ALPHA = 0.01       #  Thermal diffusivity
T_HOT = 100.0      #  Hot boundary temperature  
T_COLD = 0.0         # Cold boundary temperature  
T_INITIAL = 20.0    # Initial temperature

@dataclass
class GridConfig:
    """Configuration for the computational grid"""
    nx_global: int     # Global grid size X
    ny_global: int     # Global grid size Y
    nx_local: int       # Local grid size X (without ghost cells)
    ny_local: int      # Local grid size Y (without ghost cells)
    dx: float          # Grid spacing X
    dy: float          # Grid spacing Y
    dt: float          # Time step
    coords: Tuple[int, int]  # Process coordinates in 2D grid
    dims: Tuple[int, int]    # Process grid dimensions

class HeatSolverMPI:
    """
    MPI-parallel heat equation solver using finite differences
    
    This class handles:
    - Domain decomposition across MPI processes
    - Ghost cell exchange between neighbors
    - 5-point stencil computation
    - Boundary condition application
    """
    def __init__(self, nx_global: int, ny_global: int, comm=None):
        """
        Initialize the parallel heat solver
        
        Args:
            nx_global: Global grid points in X direction
            ny_global: Global grid points in Y direction
            comm: MPI communicator (default: MPI.COMM_WORLD)
        """
        self.comm = comm if comm else MPI.COMM_WORLD
        self.rank = self.comm.Get_rank()
        self.size = self.comm.Get_size()

        # Set up the 2D process topology
        self.setup_topology(nx_global, ny_global)

        # Initialize the grid
        self.initialize_grid()

        if self.rank == 0:
            print(f"Heat Solver MPI (Python Version)")
            print(f"Process grid: {self.config.dims[0]} x {self.config.dims[1]}")
            print(f"Global grid: {nx_global} x {ny_global}")
            print(f"Local grid: {self.config.nx_local} x {self.config.ny_local}")
            print(f"Time step: {self.config.dt:.6e}")
            print("-" * 50)

    def setup_topology(self, nx_global: int, ny_global: int):
        """Create 2D Cartesian topology for processes"""

        # Let MPI determine optimal 2D grid of processes
        dims = MPI.Compute_dims(self.size, [0, 0])

        # Create Cartesian communicator
        periods = [False, False]  # Non-periodic boundaries
        self.cart_comm = self.comm.Create_cart(dims, periods, reorder=True)

        # Get coordinates in progress grid
        coords = self.cart_comm.Get_coords(self.cart_comm.Get_rank())

        # Get neighbors (North, South, West, East)
        self.neighbors = {
            'north': self.cart_comm.Shift(0, 1)[0],
            'south': self.cart_comm.Shift(0, 1)[1],
            'west': self.cart_comm.Shift(1, -1)[0],
            'east': self.cart_comm.Shift(1, 1)[1]
        }

        # Calculate local grid size
        nx_local = nx_global // dims[0]
        ny_local = ny_global // dims[1]

        # Handle remainder - some processes get extra points
        if coords[0]  < nx_global % dims[0]:
            nx_local += 1
        if coords[1] < ny_global % dims[1]:
            ny_local += 1

        # Grid spacing
        dx = 1.0 / (nx_global - 1)
        dy = 1.0 / (ny_global - 1)

        # Stable time step (CFL condition)
        dt = 0.25 * min(dx**2, dy**2) / ALPHA

        # Store configuration
        self.config = GridConfig(
            nx_global = nx_global,
            ny_global = ny_global,
            nx_local = nx_local,
            ny_local = ny_local,
            dx=dx,
            dy=dy,
            dt=dt,
            coords=coords,
            dims = dims
        )

    def initialize_grid(self):
        """Initialize temperature field with ghost cells"""

        # Allocate arrays including ghost cells (padding of 1 on each side)
        # Shape: [nx_local + 2, ny_local + 2]
        self.u = np.full((self.config.nx_local + 2, self.config.ny_local + 2),
                        T_INITIAL, dtype=np.float64)
        self.u_new = np.full((self.config.nx_local + 2, self.config.ny_local + 2),
                            T_INITIAL, dtype=np.float64)

        # Apply initial boundary conditions
        self.apply_boundary_conditions()

    def apply_boundary_conditions(self):
        """Apply Dirichlet boundary conditions at domain edges"""

        # Top boundary (hot) - if this is the topmost process row
        if self.neighbors['north'] == MPI.PROC_NULL:
            self.u[0, :] = T_HOT
            self.u_new[0, :]  = T_HOT

        # Bottom boundary (cold) - if this is the bottommost process row
        if self.neighbors['south'] == MPI.PROC_NULL:
            self.u[-1, :] = T_COLD
            self.u_new[-1, :]  = T_COLD

        # Left boundary (cold) - if this is the leftmost process row
        if self.neighbors['west'] == MPI.PROC_NULL:
            self.u[:, 0] = T_COLD
            self.u_new[:, 0]  = T_COLD

        # Right boundary (cold) - if this is the rightmost process row
        if self.neighbors['east'] == MPI.PROC_NULL:
            self.u[:, -1] = T_COLD
            self.u_new[:, -1]  = T_COLD

    def exchange_ghost_cells(self):
        """
        Exchange ghost cells with neighboring processes
        Fixed version using Sendrecv to avoid deadlocks
        This is the key MPI communication pattern for domain decomposition.
        Each process exchanges boundary data with its 4 neighbors.
        """
       # North-South
        self.u[-1, 1:-1] = self.cart_comm.sendrecv(
            sendobj=self.u[1, 1:-1].copy(), 
            dest=self.neighbors['north'],
            source=self.neighbors['south']
        )
        
        self.u[0, 1:-1] = self.cart_comm.sendrecv(
            sendobj=self.u[-2, 1:-1].copy(), 
            dest=self.neighbors['south'],
            source=self.neighbors['north']
        )
        
        # East-West
        self.u[1:-1, -1] = self.cart_comm.sendrecv(
            sendobj=self.u[1:-1, 1].copy(), 
            dest=self.neighbors['west'],
            source=self.neighbors['east']
        )
    
        self.u[1:-1, 0] = self.cart_comm.sendrecv(
            sendobj=self.u[1:-1, -2].copy(), 
            dest=self.neighbors['east'],
            source=self.neighbors['west']
        )
 
    def apply_stencil(self):
        """
        Apply 5-point stencil for heat equation
        
        Finite difference approximation:
        u_new = u + dt * alpha * (d²u/dx² + d²u/dy²)
        
        Using central differences:
        d²u/dx² ≈ (u[i-1,j] - 2*u[i,j] + u[i+1,j]) / dx²
        d²u/dy² ≈ (u[i,j-1] - 2*u[i,j] + u[i,j+1]) / dy²
        """

        rx =  ALPHA * self.config.dt / (self.config.dx ** 2)
        ry = ALPHA * self.config.dt / (self.config.dy ** 2)

        # Apply stencil to interior points (not ghost cells)
        # Vectorized operation for better performance
        self.u_new[1:-1, 1:-1] = (
            self.u[1:-1, 1:-1] +
            rx * (self.u[:-2, 1:-1] - 2*self.u[1:-1, 1:-1] + self.u[2:, 1:-1]) +
            ry * (self.u[1:-1, :-2] - 2*self.u[1:-1, 1:-1] + self.u[1:-1, 2:])
        )

        # Swap arrays (u becomes u_new for next iteration)
        self.u, self.u_new = self.u_new, self.u

        # Reapply boundary_conditions
        self.apply_boundary_conditions()

    def gather_global_solution(self) -> Optional[np.ndarray]:
        """
        Gather the distributed solution to rank 0
        
        Returns:
            Global solution array on rank 0, None on other ranks
        """

        # Get local solution (without ghost sells)
        local_solution = self.u[1:-1, 1:-1]

        if self.size == 1:
            # Single process - judt return local solution
            return local_solution

        # Gather all local solutions to rank 0
        # First, gather the sizes
        local_size = local_solution.size
        sizes = self.comm.gather(local_size, root=0)

        # Gather the actual data
        if self.rank == 0:
            # prepare the actual data
            total_size = sum(sizes)
            gathered_data = np.empty(total_size, dtype = np.float64)
            
            # Receive from all processes
            self.comm.Gatherv(local_solution.flatten(), [gathered_data, sizes], root=0)
            
            # Reconstruct global array
            global_solution = np.zeros((self.config.nx_global, self.config.ny_global))
            
            # Place each process's data in correct position
            offset = 0
            for p in range(self.size):
                # Get process coordinates
                p_coords = self.cart_comm.Get_coords(p)
                
                # Calculate local size for this process
                p_nx_local = self.config.nx_global // self.config.dims[0]
                p_ny_local = self.config.ny_global // self.config.dims[1]
                
                if p_coords[0] < self.config.nx_global % self.config.dims[0]:
                    p_nx_local += 1
                if p_coords[1] < self.config.ny_global % self.config.dims[1]:
                    p_ny_local += 1
                
                # Calculate global indices
                i_start = p_coords[0] * (self.config.nx_global // self.config.dims[0])
                j_start = p_coords[1] * (self.config.ny_global // self.config.dims[1])
                
                # Handle remainder
                i_start += min(p_coords[0], self.config.nx_global % self.config.dims[0])
                j_start += min(p_coords[1], self.config.ny_global % self.config.dims[1])
                
                # Copy data
                data = gathered_data[offset:offset + sizes[p]].reshape(p_nx_local, p_ny_local)
                global_solution[i_start:i_start + p_nx_local, j_start:j_start + p_ny_local] = data
                offset += sizes[p]

            return global_solution
        else:
            # Other processes just send theit data
            self.comm.Gatherv(local_solution.flatten(), None, root=0)
            return None

    def save_solution(self, timestep: int, output_dir: str = "/nfs/shared"):
        """Save the solution to file (only rank 0 writes)"""

        global_solution  = self.gather_global_solution()

        if self.rank == 0 and global_solution is not None:
            filename =f"{output_dir}/heat_solution_{timestep:05d}.dat"

            # Write in same format as C version for compatibility
            with open(filename, 'w') as f:
                f.write(f"# Heat equation solution at timestep {timestep}\n ")
                f.write(f"# nx={self.config.nx_global} ny={self.config.ny_global} ")
                f.write(f"time={timestep * self.config.dt:.6f}\n")
                
                for i in range(self.config.nx_global):
                    for j in range(self.config.ny_global):
                        f.write(f"{global_solution[i, j]:.6f} ")
                    f.write("\n")
            
            print(f"Saved solution to {filename}")

    def compute_max_error(self) -> float:
        """Compute maximum change between iterations (for convergence check)"""

        # Local maximum difference
        local_max = np.max(np.abs(self.u_new[1:-1, 1:-1] - self.u[1:-1, 1:-1]))

        # Global max across all processes
        global_max = self.comm.allreduce(local_max, op=MPI.MAX)

        return global_max

    def run(self, n_steps: int, save_interval: int = 100):
        """
        Run the simulation for specified number of time steps
        
        Args:
            n_steps: Number of time steps to simulate
            save_interval: Save solution every N steps
        """

        # Save initial condition
        self.save_solution(0)

        # Start timing
        self.comm.Barrier()
        start_time = MPI.Wtime()

        # Time evolution loop
        for step in range(1, n_steps + 1):
            # Exchange ghost cells with neighbors
            self.exchange_ghost_cells()

            # Apply finite difference stencil
            self.apply_stencil()

            # Save periodically
            if step % save_interval == 0:
                if self.rank == 0:
                    print(f"Step {step} / {n_steps}")
                self.save_solution(step)

        #  End timing
        self.comm.Barrier()
        end_time = MPI.Wtime()

        # Performance metrics (rank 0 reports)
        if self.rank == 0:
            elapsed = end_time - start_time
            grid_points = self.config.nx_global * self.config.ny_global
            updates_per_sec = grid_points * n_steps / elapsed

            print("\n" + "="*50)
            print("Performance Summary")
            print("="*50)
            print(f"Grid size: {self.config.nx_global} x {self.config.ny_global}")
            print(f"Processes: {self.size}")
            print(f"Time steps: {n_steps}")
            print(f"Total time: {elapsed:.3f} seconds")
            print(f"Updates/sec: {updates_per_sec:.2e}")
            print(f"Time per step: {elapsed * 1000 / n_steps:.3f} ms")
            print(f"GFLOPS: {7 * updates_per_sec / 1e9:.2f}")  # 7 ops per point
            print("="*50)

def main():
    """Main function - parse arguments and run simulation"""

    # Parse command line arguments
    nx = int(sys.argv[1]) if len(sys.argv) > 1 else 256
    ny = int(sys.argv[2]) if len(sys.argv) > 2 else 256
    n_steps = int(sys.argv[3]) if len(sys.argv) > 3 else 1000

    # Create and run solver
    solver = HeatSolverMPI(nx, ny)
    solver.run(n_steps)

if __name__ == "__main__":
    main()      
