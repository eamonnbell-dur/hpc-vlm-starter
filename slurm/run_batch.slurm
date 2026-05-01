#!/bin/bash
# run_batch.slurm — Process one batch of images against the running vLLM server.
# Usage: sbatch slurm/run_batch.slurm batch_01

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

#SBATCH -A ${SLURM_ACCOUNT}        # Remove this line if your cluster does not use account-based billing
#SBATCH --time=${BATCH_TIME}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=${BATCH_CPUS}
#SBATCH --partition=standard       # Remove this line if your scheduler assigns a default partition for CPU jobs
#SBATCH --mem=${BATCH_MEM}
#SBATCH -J "vlm-extract"
#SBATCH -o ${LOG_DIR}/batch_extract_%j.out

module purge
module load gcc/11.4.0 openmpi/4.1.4 python/3.11.4

cd "${PROJECT_DIR}"

BATCH_DIR=$1
if [ -z "$BATCH_DIR" ]; then
    echo "Error: Provide a batch directory name (e.g., batch_01)"
    exit 1
fi

# Wait for the vLLM server to write its address
echo "Waiting for vLLM server..."
while [ ! -f "${LOG_DIR}/vllm_server_address.txt" ]; do
    sleep 30
done
sleep 60  # buffer for model to finish loading into VRAM

ADDR=$(cat "${LOG_DIR}/vllm_server_address.txt" | tr -d '\n')

echo "Starting extraction for ${BATCH_DIR} against ${ADDR}"
python "${CODE_DIR}/scripts/batch_extract.py" \
    --input-dir "${IMAGE_DIR}/${BATCH_DIR}/" \
    --output-dir "${OUTPUT_DIR}/${BATCH_DIR}/${MODEL_NAME}/" \
    --endpoint "http://${ADDR}/v1/chat/completions" \
    --model "${MODEL_NAME}" \
    --mode "${EXTRACTION_MODE}" \
    --prompt-file "${PROMPT_FILE}" \
    --prompt-file-pass-b "${PROMPT_FILE_PASS_B}" \
    --pattern "${IMAGE_PATTERN}" \
    --max-tokens "${MAX_TOKENS}" \
    --temperature "${TEMPERATURE}" \
    --workers "${WORKERS}" &
PID=$!

wait $PID

echo "Extraction finished. Syncing filesystem..."
sync
sleep 300
echo "Batch ${BATCH_DIR} complete."
