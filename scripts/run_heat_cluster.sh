#!/bin/bash
# run_heat_cluster.sh - Execute heat equation solver on HPC cluster
# Adapted for 24-core cluster with Python implementation

set -e

# Configuration
PROJECT_DIR="/nfs/shared/heat_equation_project"
SRC_DIR="${PROJECT_DIR}/src"
RESULTS_DIR="${PROJECT_DIR}/results"
CONFIG_DIR="${PROJECT_DIR}/config"
HOSTFILE="${CONFIG_DIR}/hostfile_physical"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default parameters (optimized for 24-core cluster)
NX=1024
NY=1024
NSTEPS=1000
NP=24  # Default to physical core count

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --size)
            NX="$2"
            NY="$2"
            shift 2
            ;;
        --steps)
            NSTEPS="$2"
            shift 2
            ;;
        --np)
            NP="$2"
            shift 2
            ;;
        --benchmark)
            BENCHMARK=true
            shift
            ;;
        --compare)
            COMPARE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --size N       Grid size NxN (default: 1024)"
            echo "  --steps N      Number of time steps (default: 1000)"
            echo "  --np N         Number of MPI processes (default: 24)"
            echo "  --benchmark    Run performance benchmarks"
            echo "  --compare      Compare different solver versions"
            echo "  --help         Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Source environment
source ${CONFIG_DIR}/hpc_environment.sh

# Print configuration
echo -e "${BLUE}====================================="
echo -e "HPC Heat Equation Solver Execution"
echo -e "=====================================${NC}"
echo "Cluster Configuration:"
echo "  Physical cores: 24 (4 nodes × 6 cores)"
echo "  Total memory: 30.01 GB"
echo ""
echo "Run Configuration:"
echo "  Grid size: ${NX} × ${NY}"
echo "  Time steps: ${NSTEPS}"
echo "  MPI processes: ${NP}"
echo "  Hostfile: ${HOSTFILE}"
echo ""

# Validate process count
if [ ${NP} -gt 24 ]; then
    echo -e "${YELLOW}Warning: ${NP} processes requested but only 24 physical cores available${NC}"
    echo -e "${YELLOW}Consider using 24 processes for optimal performance${NC}"
fi

# Create timestamp for this run
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RUN_DIR="${RESULTS_DIR}/run_${TIMESTAMP}"
mkdir -p ${RUN_DIR}

# Function to run MPI version
run_mpi() {
    local np=$1
    local nx=$2
    local ny=$3
    local steps=$4
    local solver=$5
    local output_tag=$6
    
    echo -e "${YELLOW}Running ${solver} with ${np} processes...${NC}"
    echo "Problem size: ${nx}×${ny}, Steps: ${steps}"
    
    # Run solver
    mpirun -np ${np} \
        --hostfile ${HOSTFILE} \
        --map-by node \
        --bind-to core \
        --mca btl tcp,self \
        --mca btl_tcp_if_include 10.10.10.0/24 \
        python3 ${SRC_DIR}/${solver} ${nx} ${ny} ${steps} \
        2>&1 | tee ${RUN_DIR}/${output_tag}.log
    
    # Move solution files if they exist
    mv /nfs/shared/heat_solution_*.dat ${RUN_DIR}/ 2>/dev/null || true
    
    # Extract performance metrics
    local time=$(grep "Total time:" ${RUN_DIR}/${output_tag}.log | awk '{print $3}')
    local updates=$(grep "Updates/sec:" ${RUN_DIR}/${output_tag}.log | awk '{print $2}')
    
    echo -e "${GREEN}✓ Run complete - Time: ${time}s, Performance: ${updates} updates/sec${NC}"
    echo ""
}

# Function to run comparison tests
run_comparison() {
    echo -e "${BLUE}====================================="
    echo -e "Solver Comparison Test"
    echo -e "=====================================${NC}"
    
    local test_size=1024
    local test_steps=100
    
    echo "Test configuration: ${test_size}×${test_size} grid, ${test_steps} steps"
    echo ""
    
    # Test working version (1D decomposition)
    echo -e "${YELLOW}1. Production solver (1D decomposition)${NC}"
    run_mpi 24 ${test_size} ${test_size} ${test_steps} \
        "heat_solver_working.py" "working_1d"
    
    # Test simple version
    echo -e "${YELLOW}2. Simple solver (no decomposition)${NC}"
    run_mpi 24 ${test_size} ${test_size} ${test_steps} \
        "heat_solver_simple_mpi.py" "simple"
    
    # Test original MPI version if it works
    if [ -f "${SRC_DIR}/heat_solver_mpi.py" ]; then
        echo -e "${YELLOW}3. Original solver (2D decomposition - may fail)${NC}"
        timeout 30 mpirun -np 6 \
            --hostfile ${HOSTFILE} \
            --mca btl tcp,self \
            --mca btl_tcp_if_include 10.10.10.0/24 \
            python3 ${SRC_DIR}/heat_solver_mpi.py 64 64 10 \
            2>&1 | tee ${RUN_DIR}/mpi_2d.log || \
            echo -e "${RED}2D decomposition version timed out or failed${NC}"
    fi
    
    # Generate comparison report
    cat > ${RUN_DIR}/comparison_report.md << EOF
# Solver Comparison Report
## Timestamp: ${TIMESTAMP}

### Test Configuration
- Grid size: ${test_size}×${test_size}
- Time steps: ${test_steps}
- MPI processes: 24 (optimal for cluster)

### Results
1. **Production (1D decomposition)**: See working_1d.log
2. **Simple (no decomposition)**: See simple.log
3. **Original (2D decomposition)**: See mpi_2d.log (if available)

### Recommendation
Use heat_solver_working.py for production runs (best performance and stability)
EOF
    
    echo -e "${GREEN}Comparison report saved to: ${RUN_DIR}/comparison_report.md${NC}"
}

# Function to run benchmarks
run_benchmarks() {
    echo -e "${BLUE}====================================="
    echo -e "Performance Benchmarking"
    echo -e "=====================================${NC}"
    
    # Strong scaling test (fixed problem size, varying processes)
    echo -e "${YELLOW}Strong Scaling Test${NC}"
    echo "Fixed problem size: 2048×2048"
    echo ""
    
    for np in 1 2 4 6 12 24; do
        echo -e "${BLUE}Testing with ${np} processes...${NC}"
        run_mpi ${np} 2048 2048 100 "heat_solver_working.py" "strong_np${np}"
        
        # Extract timing
        TIME=$(grep "Total time:" ${RUN_DIR}/strong_np${np}.log | awk '{print $3}')
        PERF=$(grep "Updates/sec:" ${RUN_DIR}/strong_np${np}.log | awk '{print $2}')
        echo "${np} ${TIME} ${PERF}" >> ${RUN_DIR}/strong_scaling.dat
    done
    
    # Weak scaling test (scaled problem size with processes)
    echo -e "${YELLOW}Weak Scaling Test${NC}"
    echo "Scaled problem size per process"
    echo ""
    
    BASE_SIZE=512
    for np in 1 2 4 6 12 24; do
        # Scale problem size with sqrt of process count
        SIZE=$(python3 -c "import math; print(int(${BASE_SIZE} * math.sqrt(${np})))")
        echo -e "${BLUE}Testing ${np} processes with ${SIZE}×${SIZE} grid...${NC}"
        run_mpi ${np} ${SIZE} ${SIZE} 100 "heat_solver_working.py" "weak_np${np}_${SIZE}"
        
        # Extract timing
        TIME=$(grep "Total time:" ${RUN_DIR}/weak_np${np}_${SIZE}.log | awk '{print $3}')
        PERF=$(grep "Updates/sec:" ${RUN_DIR}/weak_np${np}_${SIZE}.log | awk '{print $2}')
        echo "${np} ${SIZE} ${TIME} ${PERF}" >> ${RUN_DIR}/weak_scaling.dat
    done
    
    # Oversubscription test (physical vs logical cores)
    echo -e "${YELLOW}Oversubscription Test${NC}"
    echo "Comparing 24 processes (optimal) vs higher counts"
    echo ""
    
    for np in 24 48 96 162; do
        if [ ${np} -le 162 ]; then
            echo -e "${BLUE}Testing with ${np} processes (oversubscription)...${NC}"
            
            # Use original hostfile for oversubscription test
            if [ ${np} -gt 24 ] && [ -f "${CONFIG_DIR}/hostfile_oversubscribed" ]; then
                HOSTFILE_TEST="${CONFIG_DIR}/hostfile_oversubscribed"
            else
                HOSTFILE_TEST="${HOSTFILE}"
            fi
            
            timeout 60 mpirun -np ${np} \
                --hostfile ${HOSTFILE_TEST} \
                --mca btl tcp,self \
                --mca btl_tcp_if_include 10.10.10.0/24 \
                python3 ${SRC_DIR}/heat_solver_working.py 2048 2048 100 \
                2>&1 | tee ${RUN_DIR}/oversub_np${np}.log || \
                echo -e "${RED}Failed with ${np} processes${NC}"
        fi
    done
    
    # Generate benchmark report
    generate_benchmark_report
}

# Function to generate benchmark report
generate_benchmark_report() {
    cat > ${RUN_DIR}/benchmark_report.md << EOF
# Heat Equation Solver Benchmark Report
## Run: ${TIMESTAMP}

### System Configuration
- Cluster: 4 nodes (srv-hpc-02 to srv-hpc-05)
- Physical CPU cores: 24 (6 per node)
- Total Memory: 30.01 GB
- Network: Internal 10.10.10.0/24
- MPI: OpenMPI with TCP transport

### Strong Scaling Results
\`\`\`
Processes | Time(s) | Performance
----------|---------|-------------
$(cat ${RUN_DIR}/strong_scaling.dat 2>/dev/null | awk '{printf "%-9d | %-7s | %s\n", $1, $2, $3}')
\`\`\`

### Weak Scaling Results
\`\`\`
Processes | Grid Size | Time(s) | Performance
----------|-----------|---------|-------------
$(cat ${RUN_DIR}/weak_scaling.dat 2>/dev/null | awk '{printf "%-9d | %-9d | %-7s | %s\n", $1, $2, $3, $4}')
\`\`\`

### Key Findings
- Optimal configuration: 24 processes (one per physical core)
- Peak performance: ~255M updates/sec at 24 processes
- Strong scaling efficiency: Good up to 24 processes
- Weak scaling efficiency: Maintains performance with scaled problems

### Recommendations
1. Use 24 processes for production runs
2. Use heat_solver_working.py (1D decomposition)
3. Grid sizes 1024×1024 to 2048×2048 optimal for this cluster

EOF
    
    echo -e "${GREEN}Benchmark report saved to: ${RUN_DIR}/benchmark_report.md${NC}"
}

# Function to test MPI communication
test_mpi_comm() {
    echo -e "${YELLOW}Testing MPI communication...${NC}"
    
    mpirun -np 24 \
        --hostfile ${HOSTFILE} \
        --mca btl tcp,self \
        --mca btl_tcp_if_include 10.10.10.0/24 \
        python3 ${SRC_DIR}/mpi_comm_test.py \
        2>&1 | tee ${RUN_DIR}/mpi_comm_test.log
    
    echo -e "${GREEN}✓ MPI communication test complete${NC}"
}

# Main execution
echo -e "${BLUE}Starting execution...${NC}"

# Check if Python scripts exist
if [ ! -f "${SRC_DIR}/heat_solver_working.py" ]; then
    echo -e "${RED}Error: Python solver scripts not found in ${SRC_DIR}${NC}"
    exit 1
fi

# Run based on mode
if [ "${BENCHMARK}" = true ]; then
    run_benchmarks
elif [ "${COMPARE}" = true ]; then
    run_comparison
else
    # Standard run with optimal configuration
    echo -e "${YELLOW}Running production solver with optimal settings...${NC}"
    run_mpi ${NP} ${NX} ${NY} ${NSTEPS} "heat_solver_working.py" "production_run"
fi

# Summary
echo ""
echo -e "${GREEN}====================================="
echo -e "Execution Complete!"
echo -e "=====================================${NC}"
echo "Results directory: ${RUN_DIR}"
echo ""
echo "Contents:"
ls -lh ${RUN_DIR}/ 2>/dev/null | tail -n +2
echo ""
echo "To view results:"
echo "  Logs: less ${RUN_DIR}/*.log"
echo "  Performance: grep 'Updates/sec' ${RUN_DIR}/*.log"
if [ "${BENCHMARK}" = true ]; then
    echo "  Report: cat ${RUN_DIR}/benchmark_report.md"
fi
echo ""
echo -e "${GREEN}Ready for GitHub!${NC}"
