#!/bin/bash
# retry_failed.slurm — Aggregate all failure logs and re-process failed images.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

#SBATCH -A ${SLURM_ACCOUNT}
#SBATCH --time=${RETRY_TIME}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=2
#SBATCH --partition=standard
#SBATCH --mem=${RETRY_MEM}
#SBATCH -J "vlm-retry"
#SBATCH -o ${LOG_DIR}/retry_extract_%j.out

module purge
module load gcc/11.4.0 openmpi/4.1.4 python/3.11.4

cd "${PROJECT_DIR}"

ADDR=$(cat "${LOG_DIR}/vllm_server_address.txt" | tr -d '\n')
sleep 5

echo "Aggregating failed cards for model: ${MODEL_NAME}"

MASTER_FAIL_LIST="${OUTPUT_DIR}/aggregated_failures_${MODEL_NAME}.txt"
> "$MASTER_FAIL_LIST"

find "${OUTPUT_DIR}/" -name "failed_cards_${MODEL_NAME}.txt" -exec cat {} + >> "$MASTER_FAIL_LIST"

FAIL_COUNT=$(wc -l < "$MASTER_FAIL_LIST" | tr -d ' ')

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "No failures found. Exiting."
    rm "$MASTER_FAIL_LIST"
    exit 0
fi

echo "Found ${FAIL_COUNT} failed extractions. Retrying..."

python "${CODE_DIR}/scripts/batch_extract.py" \
    --file-list "$MASTER_FAIL_LIST" \
    --output-dir "${OUTPUT_DIR}/retries/${MODEL_NAME}/" \
    --endpoint "http://${ADDR}/v1/chat/completions" \
    --model "${MODEL_NAME}" \
    --mode "${EXTRACTION_MODE}" \
    --prompt-file "${PROMPT_FILE}" \
    --prompt-file-pass-b "${PROMPT_FILE_PASS_B}" \
    --max-tokens "${MAX_TOKENS}" \
    --temperature "${TEMPERATURE}" \
    --workers "${RETRY_WORKERS}" &
PID=$!

wait $PID
echo "Retry sweep complete."
