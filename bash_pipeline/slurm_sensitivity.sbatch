#!/bin/bash
# =============================================================================
# slurm_sensitivity.sbatch — lanza el loop secuencial dentro de una asignación
# Slurm, con los recursos reservados explícitamente (nohup NO reserva CPU ni
# memoria y no sustituye a Slurm).
#
#   cd /scratch/gcamteam/hindcasting/GCAM_sensitivity_analysis
#   mkdir -p logs_bash
#   sbatch bash_pipeline/slurm_sensitivity.sbatch EXP_c9b80e40 100 _999 --seed-base 10000
#
# Ajustar partición/QOS/cuenta, memoria y tiempo a las normas del DIPC.
# Medir antes memoria y duración con 1 y 3 iteraciones (sacct, ver README).
# =============================================================================
#SBATCH --job-name=gcam_sens
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=48:00:00
#SBATCH --output=logs_bash/slurm_%x_%j.out
#SBATCH --error=logs_bash/slurm_%x_%j.out
##SBATCH --partition=XXXX
##SBATCH --qos=XXXX
##SBATCH --account=XXXX

set -u
WORK_DIR="${WORK_DIR:-/scratch/gcamteam/hindcasting/GCAM_sensitivity_analysis}"
cd "$WORK_DIR" || { echo "No existe $WORK_DIR"; exit 1; }

echo "Job ${SLURM_JOB_ID:-?} en $(hostname) — $(date)"
echo "Argumentos: $*"
# Si GCAM necesita módulos (Java, Boost...), cargarlos aquí o en run-gcam.sh:
# module load ...

srun --ntasks=1 --cpus-per-task="${SLURM_CPUS_PER_TASK:-1}" bash bash_pipeline/run_sensitivity_bash.sh "$@"
rc=$?
echo "Fin $(date) — código $rc"
echo "Memoria/tiempo del trabajo: sacct -j ${SLURM_JOB_ID:-?} --format=JobID,Elapsed,MaxRSS,State,ExitCode"
exit $rc
