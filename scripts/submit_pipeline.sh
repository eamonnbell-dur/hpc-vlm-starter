#!/bin/bash
# submit_pipeline.sh — Start the vLLM server, chain all batches, queue retry sweep.
#
# Usage: ./scripts/submit_pipeline.sh [START_BATCH] [END_BATCH]
# Example: ./scripts/submit_pipeline.sh 1 14

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

cd "${PROJECT_DIR}" || exit 1

START=${1:-1}
END=${2:-14}

echo "Cleaning up old server address..."
rm -f "${LOG_DIR}/vllm_server_address.txt"
sleep 15  # allow filesystem propagation

echo "Submitting vLLM server job..."
SERVER_OUTPUT=$(sbatch "${CODE_DIR}/slurm/start_server.slurm")
echo "$SERVER_OUTPUT"
SERVER_JOBID=$(echo "$SERVER_OUTPUT" | awk '{print $4}')

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
echo "Queuing retry sweep after all batches..."
if [ -n "$PREVIOUS_JOBID" ]; then
    RETRY_OUTPUT=$(sbatch --dependency=afterok:$PREVIOUS_JOBID "${CODE_DIR}/slurm/retry_failed.slurm")
else
    RETRY_OUTPUT=$(sbatch "${CODE_DIR}/slurm/retry_failed.slurm")
fi
echo "  -> $RETRY_OUTPUT"

echo ""
echo "Pipeline submitted! Monitor with: squeue -u $USER"
