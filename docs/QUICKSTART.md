# Quick Start Guide

Get up and running with the HPC Heat Equation Solver in 5 minutes.

## Prerequisites Check

```bash
# Check if OpenMPI is installed
which mpirun
# Expected output: /usr/lib64/openmpi/bin/mpirun

# Check if Python packages are available
python3 -c "from mpi4py import MPI; import numpy as np; print('✓ All dependencies OK')"
```

If any checks fail, see [Installation](#installation) section below.

## Running Your First Simulation

### 1. Clone and Navigate

```bash
git clone https://github.com/maltsev-andrey/hpc-heat-solver.git
cd hpc-heat-solver
```

### 2. Run Default Simulation

```bash
# Single node test (4 processes)
mpirun -np 4 python3 src/heat_solver_working.py

# Expected output:
# Heat Solver - Working Version
# Global grid: 1024 x 1024
# Processes: 4
# ...
# Performance Summary
# Total time: ~X seconds
```

### 3. Run Full Cluster Benchmark

```bash
# Execute on all 24 cores across 4 compute nodes
cd scripts
./benchmark_scaling.sh

# This will test three problem sizes:
# - 1024×1024 (baseline)
# - 2048×2048 (4× larger)
# - 4096×4096 (16× larger)
```

Results are saved to `benchmark_results/` with timestamp.

## Common Commands

### Run with Custom Grid Size

```bash
# Small test (512×512)
mpirun -np 24 --hostfile config/hostfile_physical \
    python3 src/heat_solver_working.py --nx 512 --ny 512 --steps 1000

# Large simulation (8192×8192)
mpirun -np 24 --hostfile config/hostfile_physical \
    python3 src/heat_solver_working.py --nx 8192 --ny 8192 --steps 500
```

### Run on Specific Nodes

```bash
# Create custom hostfile
cat > my_hostfile << EOF
srv-hpc-02 slots=6
srv-hpc-03 slots=6
EOF

# Run on selected nodes only
mpirun -np 12 --hostfile my_hostfile \
    python3 src/heat_solver_working.py
```

### Adjust Time Steps

```bash
# More time steps for longer simulation
mpirun -np 24 --hostfile config/hostfile_physical \
    python3 src/heat_solver_working.py --steps 5000

# Fewer steps for quick test
mpirun -np 24 --hostfile config/hostfile_physical \
    python3 src/heat_solver_working.py --steps 100
```

## Installation

### If OpenMPI is Missing

```bash
# RHEL/CentOS
sudo dnf install openmpi openmpi-devel

# Ubuntu/Debian
sudo apt-get install openmpi-bin libopenmpi-dev

# Load module (if using module system)
module load mpi/openmpi-x86_64
```

### If Python Packages are Missing

```bash
# Install mpi4py and numpy
pip3 install --user mpi4py numpy

# Verify installation
python3 -c "from mpi4py import MPI; print(f'MPI version: {MPI.Get_version()}')"
```

### If Network Issues Occur

If you see warnings about network interfaces:

```bash
# Add to ~/.bashrc or run before mpirun
export OMPI_MCA_btl_tcp_if_include="10.10.10.0/24"
export OMPI_MCA_btl_base_warn_component_unused="0"

# Or use in command line
mpirun --mca btl_tcp_if_include 10.10.10.0/24 ...
```

## Understanding the Output

### Progress Indicators

```
Progress: 10%
Progress: 20%
...
Progress: 100%
```
Shows simulation advancement through time steps.

### Performance Summary

```
==================================================
Performance Summary
==================================================
Grid size: 1024 x 1024          ← Problem size
Processes: 24                   ← MPI processes used
Time steps: 1000                ← Iterations completed
Total time: 120.112 seconds     ← Wall-clock time
Updates/sec: 8.73e+06           ← Throughput metric
Time per step: 120.112 ms       ← Per-iteration time
Center temperature: 47.82°C     ← Solution validation
==================================================
```

**Key Metrics:**
- **Updates/sec:** Higher is better (measures computational throughput)
- **Time per step:** Lower is better (measures iteration efficiency)
- **Center temperature:** Should be reasonable (0-100°C) for stable solution

## Troubleshooting

### Problem: "mpirun not found"

**Solution:**
```bash
# Load OpenMPI module
module load mpi/openmpi-x86_64

# Or add to PATH
export PATH=$PATH:/usr/lib64/openmpi/bin
```

### Problem: "No module named 'mpi4py'"

**Solution:**
```bash
pip3 install --user mpi4py
# Ensure ~/.local/bin is in PATH
```

### Problem: "Permission denied" on compute nodes

**Solution:**
```bash
# Check SSH keys
ssh-copy-id srv-hpc-02
ssh-copy-id srv-hpc-03
# ... repeat for all nodes
```

### Problem: Slow performance

**Check:**
1. Are all nodes responding? `mpirun -np 24 hostname`
2. Is NFS mounted? `df -h | grep nfs`
3. Are processes distributed? Check `--map-by node` flag

### Problem: "Invalid if_inexclude" warning

**Solution:**
```bash
# Use correct network subnet
mpirun --mca btl_tcp_if_include 10.10.10.0/24 \
    --mca btl_base_warn_component_unused 0 \
    python3 src/heat_solver_working.py
```

## Next Steps

1. **Review Results:** Check detailed analysis in [RESULTS.md](RESULTS.md)
2. **Understand Code:** Read solver implementation in `src/heat_solver_working.py`
3. **Run Variations:** Experiment with different grid sizes and parameters
4. **GPU Acceleration:** Explore CUDA version for Tesla P100 node (coming soon)
5. **Visualization:** Add output files for ParaView/VisIt visualization

## Getting Help

- **GitHub Issues:** Report bugs or ask questions
- **Documentation:** See full [README.md](README.md) for architecture details
- **Performance Analysis:** Review [RESULTS.md](RESULTS.md) for benchmarks

## Performance Expectations

**Typical Results on 24-core Cluster:**

| Grid Size | Expected Time | Updates/sec |
|-----------|---------------|-------------|
| 512²      | ~30s          | ~8-9M       |
| 1024²     | ~120s         | ~8-9M       |
| 2048²     | ~500s         | ~8-9M       |
| 4096²     | ~2000s        | ~8-9M       |

If your results significantly differ, check system load and network configuration.

---

**Happy Computing!** 🚀

For questions or contributions, please open an issue on GitHub.
