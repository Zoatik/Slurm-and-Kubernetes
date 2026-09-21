#!/bin/bash
#SBATCH --job-name=my_test_job
#SBATCH --output=output_%j.log
#SBATCH --error=error_%j.log
#SBATCH --partition=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=01:00:00

cd ../scripts

# 3. Run your program
echo "Job started on $(date)"
sh count_to_1M
echo "Job finished on $(date)"
