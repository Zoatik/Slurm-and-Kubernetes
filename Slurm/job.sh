#!/bin/bash
#SBATCH --job-name=my_test_job
#SBATCH --output=output_%j.log
#SBATCH --error=error_%j.log
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64M
#SBATCH --time=01:00:00
#SBATCH --output=/data/results/output_%j.out

set -e

# 3. Run your program
echo "Job started on $(date)"
bash count_to_1M
echo "Job finished on $(date)"
