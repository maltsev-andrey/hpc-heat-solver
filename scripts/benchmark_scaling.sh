# Create benchmark script
#!/bin/bash
#
# HPC Heat Equation Solver - Scaling Benchmark Suite
# Tests weak scaling performance across different grid sizes
#

chmod +x "$0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SOLVER_SCRIPT="$PROJECT_ROOT/src/heat_solver_working.py"
HOSTFILE="$PROJECT_ROOT/config/hostfile_physical"
RESULTS_DIR="$PROJECT_ROOT/benchmark_results"

# MPI configuration for internal network
export OMPI_MCA_btl_tcp_if_include="10.10.10.0/24"
export OMPI_MCA_btl_base_warn_component_unused="0"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Benchmark timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_FILE="$RESULTS_DIR/scaling_benchmark_$TIMESTAMP.txt"

# System information
echo "=======================================" | tee "$RESULTS_FILE"
echo "HPC Heat Equation Scaling Benchmark" | tee -a "$RESULTS_FILE"
echo "=======================================" | tee -a "$RESULTS_FILE"
echo "Date: $(date)" | tee -a "$RESULTS_FILE"
echo "Cluster: srv-hpc-01 through srv-hpc-05" | tee -a "$RESULTS_FILE"
echo "Processes: 24 (4 nodes × 6 cores)" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# Benchmark configurations
# Format: "GRID_SIZE TIME_STEPS DESCRIPTION"
BENCHMARKS=(
    "1024 1000 Baseline"
    "2048 1000 2x_Grid"
    "4096 1000 4x_Grid"
)

echo "Running benchmark suite..." | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# Run each benchmark
for benchmark in "${BENCHMARKS[@]}"; do
    read -r GRID_SIZE TIME_STEPS DESC <<< "$benchmark"
    
    echo "===================================================" | tee -a "$RESULTS_FILE"
    echo "Benchmark: $DESC" | tee -a "$RESULTS_FILE"
    echo "Grid: ${GRID_SIZE}×${GRID_SIZE}, Steps: $TIME_STEPS" | tee -a "$RESULTS_FILE"
    echo "===================================================" | tee -a "$RESULTS_FILE"
    
    # Run the solver and capture output
    OUTPUT=$(mpirun --hostfile "$HOSTFILE" \
                    -np 24 \
                    --map-by node \
                    python3 "$SOLVER_SCRIPT" \
                    --nx "$GRID_SIZE" \
                    --ny "$GRID_SIZE" \
                    --steps "$TIME_STEPS" 2>&1)
    
    echo "$OUTPUT" | tee -a "$RESULTS_FILE"
    echo "" | tee -a "$RESULTS_FILE"
    
    # Brief pause between runs
    sleep 2
done

echo "===================================================" | tee -a "$RESULTS_FILE"
echo "Benchmark Complete!" | tee -a "$RESULTS_FILE"
echo "Results saved to: $RESULTS_FILE" | tee -a "$RESULTS_FILE"
echo "===================================================" | tee -a "$RESULTS_FILE"

# Generate summary
echo "" | tee -a "$RESULTS_FILE"
echo "Summary Table:" | tee -a "$RESULTS_FILE"
echo "Grid Size | Time Steps | Total Time | Updates/sec | Time/Step" | tee -a "$RESULTS_FILE"
echo "----------|------------|------------|-------------|----------" | tee -a "$RESULTS_FILE"

# Extract key metrics (this is a simple grep-based extraction)
grep -A 20 "Performance Summary" "$RESULTS_FILE" | grep "Grid size\|Total time\|Updates/sec\|Time per step" | tee -a "$RESULTS_FILE"

