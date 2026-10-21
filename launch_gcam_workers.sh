#!/bin/bash

#SBATCH --job-name=gcam_mc
#SBATCH --qos=regular
#SBATCH --time=1-00:00:00

#----- Worker array: 20 workers, maximum 20 simultaneous -----
#SBATCH --array=2-21%20

#----- Resources per worker -----
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G

#----- Slurm logs -----
#SBATCH --output=slurm_worker_%A_%a.out
#SBATCH --error=slurm_worker_%A_%a.err

#----- Go to working directory -----
cd /scratch/gcamteam/hindcasting/GCAM_sensitivity_analysis || exit 1

#----- Worker suffix -----
suffix=$(printf "_%02d" "$SLURM_ARRAY_TASK_ID")

#----- Experiment -----
experiment_id="EXP_c9b80e40"

#----- Worker log -----
log_file="runSensAn_allParams_monteCarlo${suffix}.log"

#----- Worker information -----
echo "=================================================="
echo "Worker:       $SLURM_ARRAY_TASK_ID"
echo "Suffix:       $suffix"
echo "Experiment:   $experiment_id"
echo "Node:         $(hostname)"
echo "Job ID:       $SLURM_JOB_ID"
echo "Array ID:     $SLURM_ARRAY_TASK_ID"
echo "Start:        $(date)"
echo "Memory:       32G"
echo "CPUs:         1"
echo "=================================================="

#----- Check R -----
echo "Rscript:"
$HOME/.conda/envs/r44/bin/Rscript --version || exit 1

#----- Run worker -----
$HOME/.conda/envs/r44/bin/Rscript \
    runSensAn_allParams_monteCarlo.R \
    "$experiment_id" \
    "$suffix" \
    > "$log_file" 2>&1

status=$?

#----- Final information -----
echo "=================================================="
echo "Worker finished"
echo "Suffix:       $suffix"
echo "Experiment:   $experiment_id"
echo "Node:         $(hostname)"
echo "Job ID:       $SLURM_JOB_ID"
echo "Exit code:    $status"
echo "End:          $(date)"
echo "=================================================="

exit $status
