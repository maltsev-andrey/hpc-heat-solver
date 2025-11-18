#!/bin/bash
# setup_permanent_hpc_gpu_config.sh
# Permanent configuration for HPC+GPU cluster integration
# Run once to configure the entire cluster for all future projectsi

chmod +x "$0"

set -e

echo "=============================================="
echo "Permanent HPC+GPU Cluster Configuration Setup"
echo "=============================================="

# Configuration variables
NFS_DIR="/nfs/shared"
CONFIG_DIR="${NFS_DIR}/cluster_config"
NODES_COMPUTE="srv-hpc-02 srv-hpc-03 srv-hpc-04 srv-hpc-05"
NODE_GPU="srv-tesla-bme"
NODE_HEAD="srv-hpc-01"

# Create configuration directory
mkdir -p ${CONFIG_DIR}

# ===========================
# 1. PERMANENT MPI CONFIGURATION
# ===========================
echo "Step 1: Creating permanent MPI configuration..."

cat > ${CONFIG_DIR}/openmpi-mca-params.conf << 'EOF'
# Permanent OpenMPI Configuration for HPC+GPU Cluster
# This file should be placed in ~/.openmpi/mca-params.conf on all nodes

# Force TCP transport (stable for dual-network setup)
btl = tcp,self

# Use internal network for compute nodes
btl_tcp_if_include = 10.10.10.0/24

# Define private networks
opal_net_private_ipv4 = 10.10.10.0/24

# Disable OFI/libfabric (causes subnet issues)
mtl = ^ofi

# Performance tuning
#btl_tcp_sndbuf = 0
#btl_tcp_rcvbuf = 0
#btl_tcp_rdma_pipeline_send_length = 1048576
#btl_tcp_rdma_pipeline_frag_size = 1048576

# Process binding for performance
#hwloc_base_binding_policy = core
#rmaps_base_mapping_policy = slot

# Increase timeout for large jobs
mpi_preconnect_all = 1
orte_abort_timeout = 60
EOF

# Deploy to all nodes
for node in ${NODE_HEAD} ${NODES_COMPUTE} ${NODE_GPU}; do
    echo "  Configuring $node..."
    ssh $node "mkdir -p ~/.openmpi && cp ${CONFIG_DIR}/openmpi-mca-params.conf ~/.openmpi/mca-params.conf" 2>/dev/null || \
    echo "    Note: Configure $node manually if needed"
done

# ===========================
# 2. CREATE ALL HOSTFILE VARIANTS
# ===========================
echo ""
echo "Step 2: Creating hostfile configurations..."

# CPU-only hostfile (internal network)
cat > ${CONFIG_DIR}/hostfile_cpu << 'EOF'
# CPU-only configuration (compute nodes)
10.10.10.1 slots=1
10.10.10.11 slots=6
10.10.10.12 slots=6
10.10.10.13 slots=6
10.10.10.14 slots=6
EOF

# GPU-only hostfile
cat > ${CONFIG_DIR}/hostfile_gpu << 'EOF'
# GPU-only configuration (Tesla P100 node)
170.168.1.13 slots=8
EOF

# Hybrid CPU+GPU hostfile
cat > ${CONFIG_DIR}/hostfile_hybrid << 'EOF'
# Hybrid CPU+GPU configuration
# Head node (coordinator)
10.10.10.1 slots=1
# Compute nodes (MPI workers)
10.10.10.11 slots=6
10.10.10.12 slots=6
10.10.10.13 slots=6
10.10.10.14 slots=6
# GPU node (CUDA acceleration)
170.168.1.13 slots=8
EOF

# Development/testing hostfile
cat > ${CONFIG_DIR}/hostfile_dev << 'EOF'
# Development configuration (small scale)
10.10.10.1 slots=1
10.10.10.11 slots=2
170.168.1.13 slots=1
EOF

# ===========================
# 3. ENVIRONMENT MODULE SYSTEM
# ===========================
echo ""
echo "Step 3: Setting up environment modules..."

cat > ${CONFIG_DIR}/hpc_environment.sh << 'EOF'
#!/bin/bash
# HPC Cluster Environment Setup
# Source this file or add to ~/.bashrc

# Base paths
export HPC_ROOT=/nfs/shared
export HPC_CONFIG=${HPC_ROOT}/cluster_config
export HPC_APPS=${HPC_ROOT}/applications
export HPC_DATA=${HPC_ROOT}/data
export HPC_SCRATCH=${HPC_ROOT}/scratch

# Python environment
export PYTHONPATH=${HPC_ROOT}/python_libs:$PYTHONPATH
export PATH=$HOME/.local/bin:$PATH

# MPI Configuration
export OMPI_MCA_btl="tcp,self"
export OMPI_MCA_btl_tcp_if_include="10.10.10.0/24,170.168.1.0/24"
export OMPI_MCA_mtl="^ofi"

# CUDA Configuration (for GPU nodes)
if [[ $(hostname) == "srv-tesla-bme" ]] || [[ $(hostname) == "srv-hpc-01" ]]; then
    export CUDA_HOME=/usr/local/cuda
    export PATH=$CUDA_HOME/bin:$PATH
    export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
    export CUDA_VISIBLE_DEVICES=0
fi

# Convenience aliases
alias mpi-cpu='mpirun --hostfile ${HPC_CONFIG}/hostfile_cpu'
alias mpi-gpu='mpirun --hostfile ${HPC_CONFIG}/hostfile_gpu'
alias mpi-hybrid='mpirun --hostfile ${HPC_CONFIG}/hostfile_hybrid'
alias mpi-dev='mpirun --hostfile ${HPC_CONFIG}/hostfile_dev'

# Function to check cluster status
hpc_status() {
    echo "HPC Cluster Status:"
    echo "=================="
    for node in srv-hpc-01 srv-hpc-02 srv-hpc-03 srv-hpc-04 srv-hpc-05 srv-tesla-bme; do
        echo -n "$node: "
        ssh -o ConnectTimeout=2 $node "hostname -I" 2>/dev/null || echo "offline"
    done
}

# Function to run MPI jobs easily
run_mpi() {
    local mode=$1
    shift
    case $mode in
        cpu)
            mpirun --hostfile ${HPC_CONFIG}/hostfile_cpu "$@"
            ;;
        gpu)
            mpirun --hostfile ${HPC_CONFIG}/hostfile_gpu "$@"
            ;;
        hybrid)
            mpirun --hostfile ${HPC_CONFIG}/hostfile_hybrid "$@"
            ;;
        *)
            echo "Usage: run_mpi [cpu|gpu|hybrid] <command>"
            ;;
    esac
}

if [[ $- == *i* ]]; then
    echo "HPC Environment loaded. Type 'hpc_status' to check cluster."
fi
EOF

# ===========================
# 4. JOB SUBMISSION SCRIPTS
# ===========================
echo ""
echo "Step 4: Creating job submission templates..."

# CPU-only job template
cat > ${CONFIG_DIR}/submit_cpu_job.sh << 'EOF'
#!/bin/bash
# Template for CPU-only MPI jobs

#-- Job Configuration --#
JOB_NAME="cpu_job"
NP=40  # Number of processes
PROGRAM="$1"
ARGS="${@:2}"

#-- Execute --#
echo "Starting CPU job: $JOB_NAME"
echo "Processes: $NP"
echo "Program: $PROGRAM"
echo "Time: $(date)"
echo "------------------------"

source /nfs/shared/cluster_config/hpc_environment.sh

mpirun -np $NP \
    --hostfile ${HPC_CONFIG}/hostfile_cpu \
    --output-filename logs/${JOB_NAME} \
    $PROGRAM $ARGS

echo "Job completed: $(date)"
EOF

# GPU job template
cat > ${CONFIG_DIR}/submit_gpu_job.sh << 'EOF'
#!/bin/bash
# Template for GPU jobs (single node)

#-- Job Configuration --#
JOB_NAME="gpu_job"
PROGRAM="$1"
ARGS="${@:2}"

#-- Execute --#
echo "Starting GPU job: $JOB_NAME"
echo "Node: srv-tesla-bme"
echo "Program: $PROGRAM"
echo "Time: $(date)"
echo "------------------------"

source /nfs/shared/cluster_config/hpc_environment.sh

ssh srv-tesla-bme "cd $(pwd) && $PROGRAM $ARGS"

echo "Job completed: $(date)"
EOF

# Hybrid CPU+GPU job template
cat > ${CONFIG_DIR}/submit_hybrid_job.sh << 'EOF'
#!/bin/bash
# Template for hybrid CPU+GPU jobs

#-- Job Configuration --#
JOB_NAME="hybrid_job"
NP_CPU=40     # CPU processes
NP_GPU=1      # GPU processes
PROGRAM="$1"
ARGS="${@:2}"

#-- Execute --#
echo "Starting Hybrid job: $JOB_NAME"
echo "CPU Processes: $NP_CPU"
echo "GPU Processes: $NP_GPU"
echo "Program: $PROGRAM"
echo "Time: $(date)"
echo "------------------------"

source /nfs/shared/cluster_config/hpc_environment.sh

# Launch MPI job with CPU and GPU nodes
mpirun \
    --hostfile ${HPC_CONFIG}/hostfile_hybrid \
    -np $((NP_CPU + NP_GPU)) \
    --output-filename logs/${JOB_NAME} \
    $PROGRAM $ARGS

echo "Job completed: $(date)"
EOF

chmod +x ${CONFIG_DIR}/*.sh

# ===========================
# 5. PROJECT STRUCTURE TEMPLATE
# ===========================
echo ""
echo "Step 5: Creating project template structure..."

cat > ${CONFIG_DIR}/create_project.sh << 'EOF'
#!/bin/bash
# Create new HPC+GPU project with proper structure

PROJECT_NAME=$1
if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $0 <project_name>"
    exit 1
fi

PROJECT_DIR="/nfs/shared/projects/$PROJECT_NAME"

echo "Creating project: $PROJECT_NAME"

# Create directory structure
mkdir -p $PROJECT_DIR/{src,build,data,results,logs,scripts}
mkdir -p $PROJECT_DIR/src/{cpu,gpu,hybrid}

# Create project README
cat > $PROJECT_DIR/README.md << README
# Project: $PROJECT_NAME

## Directory Structure
- src/cpu/    - CPU-only code (MPI)
- src/gpu/    - GPU-only code (CUDA)
- src/hybrid/ - Hybrid CPU+GPU code
- build/      - Compiled binaries
- data/       - Input data
- results/    - Output results
- logs/       - Job logs
- scripts/    - Helper scripts

## Running Jobs

### CPU-only:
\`\`\`bash
/nfs/shared/cluster_config/submit_cpu_job.sh ./build/my_program
\`\`\`

### GPU-only:
\`\`\`bash
/nfs/shared/cluster_config/submit_gpu_job.sh ./build/my_gpu_program
\`\`\`

### Hybrid:
\`\`\`bash
/nfs/shared/cluster_config/submit_hybrid_job.sh ./build/my_hybrid_program
\`\`\`

## Project created: $(date)
README

# Create Makefile template
cat > $PROJECT_DIR/Makefile << MAKEFILE
# Makefile for $PROJECT_NAME

CC = gcc
MPICC = mpicc
NVCC = nvcc
CFLAGS = -O3 -Wall
MPIFLAGS = \$(CFLAGS)
NVCCFLAGS = -O3 -arch=sm_60

SRC_DIR = src
BUILD_DIR = build

all: cpu gpu hybrid

cpu:
	\$(MPICC) \$(MPIFLAGS) \$(SRC_DIR)/cpu/*.c -o \$(BUILD_DIR)/program_cpu

gpu:
	\$(NVCC) \$(NVCCFLAGS) \$(SRC_DIR)/gpu/*.cu -o \$(BUILD_DIR)/program_gpu

hybrid:
	\$(MPICC) \$(MPIFLAGS) -c \$(SRC_DIR)/hybrid/*.c
	\$(NVCC) \$(NVCCFLAGS) -c \$(SRC_DIR)/hybrid/*.cu
	\$(MPICC) *.o -L/usr/local/cuda/lib64 -lcudart -o \$(BUILD_DIR)/program_hybrid

clean:
	rm -f \$(BUILD_DIR)/* *.o

.PHONY: all cpu gpu hybrid clean
MAKEFILE

echo "Project $PROJECT_NAME created at $PROJECT_DIR"
EOF

chmod +x ${CONFIG_DIR}/create_project.sh

# ===========================
# 6. DEPLOY TO ALL NODES
# ===========================
echo ""
echo "Step 6: Deploying configuration to all nodes..."

# Add environment setup to bashrc on all nodes
for node in ${NODE_HEAD} ${NODES_COMPUTE} ${NODE_GPU}; do
    echo "  Updating $node ~/.bashrc..."
    ssh $node "grep -q 'HPC Environment' ~/.bashrc || echo -e '\n# HPC Environment\nsource ${CONFIG_DIR}/hpc_environment.sh' >> ~/.bashrc" 2>/dev/null || \
    echo "    Note: Update $node manually if needed"
done

# ===========================
# 7. VERIFICATION
# ===========================
echo ""
echo "Step 7: Verifying configuration..."

# Test MPI with different configurations
echo "Testing CPU configuration..."
mpirun -np 6 --hostfile ${CONFIG_DIR}/hostfile_cpu hostname

echo ""
echo "Testing network connectivity..."
mpirun -np 2 --hostfile ${CONFIG_DIR}/hostfile_dev \
    python3 -c "from mpi4py import MPI; print(f'Rank {MPI.COMM_WORLD.Get_rank()} OK')"

# ===========================
# 8. CREATE DOCUMENTATION
# ===========================
cat > ${CONFIG_DIR}/CLUSTER_USAGE.md << 'DOCS'
# HPC+GPU Cluster Usage Guide

## Architecture
```
External Network (170.168.1.0/24):
  srv-hpc-01 (head) -----> srv-tesla-bme (GPU)
       |
Internal Network (10.10.10.0/24):
       |
  [srv-hpc-02] [srv-hpc-03] [srv-hpc-04] [srv-hpc-05]
```

## Where to Run Jobs

### 1. CPU-only MPI jobs: Run from ANY node
- Best from: srv-hpc-01 (head node)
- Can also run from: Any compute node
- Uses: Internal network (10.10.10.x)

### 2. GPU-only jobs: Run from srv-hpc-01 or srv-tesla-bme
- Best from: srv-tesla-bme directly
- Or SSH from: srv-hpc-01
- Uses: External network (170.168.1.x)

### 3. Hybrid CPU+GPU jobs: MUST run from srv-hpc-01
- Only srv-hpc-01 can coordinate both networks
- Manages: Both internal and external networks

## Quick Commands

```bash
# Load environment
source /nfs/shared/cluster_config/hpc_environment.sh

# Check cluster status
hpc_status

# Run MPI job (CPU)
run_mpi cpu python3 my_program.py

# Run GPU job
ssh srv-tesla-bme python3 my_cuda_program.py

# Run hybrid job
run_mpi hybrid python3 my_hybrid_program.py

# Create new project
/nfs/shared/cluster_config/create_project.sh my_project_name
```

## Network Rules
1. Compute nodes (srv-hpc-02 to 05): Internal network ONLY
2. GPU node (srv-tesla-bme): External network ONLY
3. Head node (srv-hpc-01): Bridge between both networks

## Best Practices
1. Develop on head node (srv-hpc-01)
2. Store all data in /nfs/shared
3. Use hostfile_cpu for CPU jobs
4. Use hostfile_hybrid for GPU+CPU jobs
5. Always source hpc_environment.sh

## Troubleshooting

### MPI fails to connect
- Check: Are you using the right hostfile?
- Fix: Use hostfile_cpu for internal network

### GPU not found
- Check: Are you on srv-tesla-bme or srv-hpc-01?
- Fix: SSH to correct node

### Slow performance
- Check: Is MPI using TCP? (check with --mca btl_base_verbose 100)
- Fix: Ensure btl = tcp,self in MPI config
DOCS

echo ""
echo "=============================================="
echo "✅ Permanent Configuration Complete!"
echo "=============================================="
echo ""
echo "Configuration directory: ${CONFIG_DIR}"
echo ""
echo "Next steps:"
echo "1. Source the environment: source ${CONFIG_DIR}/hpc_environment.sh"
echo "2. Test CPU job: run_mpi cpu hostname"
echo "3. Test GPU: ssh srv-tesla-bme nvidia-smi"
echo "4. Read docs: less ${CONFIG_DIR}/CLUSTER_USAGE.md"
echo ""
echo "To create a new project:"
echo "  ${CONFIG_DIR}/create_project.sh my_project_name"
echo ""
echo "IMPORTANT:"
echo "- CPU-only jobs: Can run from any node"
echo "- GPU-only jobs: Run from srv-tesla-bme"
echo "- Hybrid jobs: MUST run from srv-hpc-01"
