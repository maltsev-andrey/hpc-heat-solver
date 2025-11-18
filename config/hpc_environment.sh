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
export OMPI_MCA_btl="tcp,self,vader"
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
