# Installation Guide

## System Requirements

- RHEL 9.5 or compatible
- OpenMPI 4.x installed
- Python 3.9+
- NFS shared storage
- Minimum 6 CPU cores (optimal: 40+)

## Step-by-Step Installation

### 1. Network Configuration

Ensure proper dual-network setup:
- External: 170.168.1.0/24 (head node only)
- Internal: 10.10.10.0/24 (all compute nodes)

### 2. NFS Setup
```bash
# On head node (srv-hpc-01)
sudo mkdir -p /nfs/shared
sudo exportfs -a

# On compute nodes
sudo mount -t nfs 10.10.10.1:/nfs/shared /nfs/shared
```

### 3. MPI Configuration
```bash
# Create MPI configuration
cat > ~/.openmpi/mca-params.conf << EOF
btl = tcp,self
btl_tcp_if_include = 10.10.10.0/24
mtl = ^ofi
mpi_preconnect_mpi = 1
EOF

# Copy to all nodes
for node in srv-hpc-02 srv-hpc-03 srv-hpc-04 srv-hpc-05; do
    scp ~/.openmpi/mca-params.conf $node:~/.openmpi/
done
```

### 4. Python Package Installation
```bash
# Download packages on head node
cd /nfs/shared/python_packages
pip3 download numpy scipy matplotlib mpi4py

# Install on each compute node
for node in srv-hpc-02 srv-hpc-03 srv-hpc-04 srv-hpc-05; do
    ssh $node "pip3 install --user /nfs/shared/python_packages/*.whl"
done
```

### 5. Environment Setup
```bash
# Add to ~/.bashrc
export PATH=$HOME/.local/bin:$PATH
export PYTHONPATH=/nfs/shared/python_libs:$PYTHONPATH
source /nfs/shared/cluster_config/hpc_environment.sh
```

### 6. Verification
```bash
# Test MPI
mpirun -np 6 --hostfile /nfs/shared/cluster_config/hostfile_cpu hostname

# Test Python MPI
mpirun -np 6 --hostfile /nfs/shared/cluster_config/hostfile_cpu \
    python3 -c "from mpi4py import MPI; print(f'Rank {MPI.COMM_WORLD.Get_rank()} ready')"
```
