#!/bin/bash
# resubmit_batches.sh — Resubmit batches WITHOUT restarting the vLLM server.
# Skip-on-exists means only missing images get processed.
#
# Usage: ./scripts/resubmit_batches.sh [START_BATCH] [END_BATCH]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

cd "${PROJECT_DIR}" || exit 1

START=${1:-1}
END=${2:-14}

if [ ! -f "${LOG_DIR}/vllm_server_address.txt" ]; then
    echo "ERROR: No server address file found. Is the vLLM server running?"
    echo "Check with: squeue -u $USER"
    exit 1
fi

echo "Server address found: $(cat "${LOG_DIR}/vllm_server_address.txt")"
echo "Resubmitting batches ${START}-${END} (skip-on-exists handles dedup)..."

PREVIOUS_JOBID=""

for i in $(seq -w $START $END); do
    BATCH_NAME="batch_$i"
    echo "Queuing $BATCH_NAME..."

    if [ -z "$PREVIOUS_JOBID" ]; then
        BATCH_OUTPUT=$(sbatch "${CODE_DIR}/slurm/run_batch.slurm" "$BATCH_NAME")
    else
        BATCH_OUTPUT=$(sbatch --dependency=afterok:$PREVIOUS_JOBID "${CODE_DIR}/slurm/run_batch.slurm" "$BATCH_NAME")
    fi

    echo "  -> $BATCH_OUTPUT"
    PREVIOUS_JOBID=$(echo "$BATCH_OUTPUT" | awk '{print $4}')
done

echo ""
echo "Queuing retry sweep after all batches complete..."
if [ -n "$PREVIOUS_JOBID" ]; then
    RETRY_OUTPUT=$(sbatch --dependency=afterok:$PREVIOUS_JOBID "${CODE_DIR}/slurm/retry_failed.slurm")
else
    RETRY_OUTPUT=$(sbatch "${CODE_DIR}/slurm/retry_failed.slurm")
fi
echo "  -> $RETRY_OUTPUT"

echo ""
echo "Done! Batches + retry sweep queued."
echo "Monitor with: squeue -u $USER"
