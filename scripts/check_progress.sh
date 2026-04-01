#!/bin/bash
# check_progress.sh — Live status dashboard for the extraction pipeline.
# Usage: ./scripts/check_progress.sh
# Auto-refresh: watch -n 60 ./scripts/check_progress.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

cd "${PROJECT_DIR}" || exit 1

# If TOTAL_IMAGES is 0, count them dynamically
if [ "${TOTAL_IMAGES}" -eq 0 ]; then
    TOTAL_IMAGES=$(find "${IMAGE_DIR}" -name "${IMAGE_PATTERN}" -type f 2>/dev/null | wc -l | awk '{print $1}')
fi
if [ "${TOTAL_IMAGES}" -eq 0 ]; then
    echo "No images found in ${IMAGE_DIR}. Set TOTAL_IMAGES in config.sh."
    exit 1
fi

SERVER_JOB="vlm-server"
EXTRACT_JOB="vlm-extract"

echo "=========================================================="
echo "           HPC VLM EXTRACTION PIPELINE STATUS"
echo "=========================================================="
echo ""
echo " Model: ${MODEL_NAME}"
echo " Images: ${IMAGE_DIR}"
echo ""

# 1. Server status
SERVER_INFO=$(sacct -u "$USER" -n -X -s RUNNING --name="$SERVER_JOB" --format=JobID,Elapsed -P 2>/dev/null | head -n 1)
if [ -n "$SERVER_INFO" ]; then
    S_ID=$(echo "$SERVER_INFO" | cut -d'|' -f1)
    S_TIME=$(echo "$SERVER_INFO" | cut -d'|' -f2)
    echo " SERVER:    RUNNING (Job ${S_ID}, Uptime: ${S_TIME})"
else
    PENDING_SERVER=$(squeue -u "$USER" -a -h -n "$SERVER_JOB" -t PD 2>/dev/null | wc -l | awk '{print $1}')
    if [ "$PENDING_SERVER" -gt 0 ]; then
        echo " SERVER:    PENDING (waiting for GPU allocation)"
    else
        echo " SERVER:    STOPPED"
    fi
fi

# 2. Active batch
BATCH_JOB_INFO=$(squeue -u "$USER" -a -n "$EXTRACT_JOB" -h -t R -O "JobId,TimeUsed" 2>/dev/null | head -n 1)
if [ -n "$BATCH_JOB_INFO" ]; then
    JOB_ID=$(echo "$BATCH_JOB_INFO" | awk '{print $1}')
    UPTIME=$(echo "$BATCH_JOB_INFO" | awk '{print $2}')

    LOG_FILE=$(ls -t "${LOG_DIR}"/batch_extract_*_${JOB_ID}.out "${LOG_DIR}"/batch_extract_${JOB_ID}.out 2>/dev/null | head -1)
    BATCH_DIR=""
    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        BATCH_DIR=$(grep -o "batch_[0-9][0-9]*" "$LOG_FILE" | head -n 1)
    fi

    if [ -n "$BATCH_DIR" ]; then
        echo " ACTIVE:    ${BATCH_DIR} (Job ${JOB_ID}, Running: ${UPTIME})"
    else
        echo " ACTIVE:    Job ${JOB_ID} (Running: ${UPTIME})"
    fi
else
    PENDING=$(squeue -u "$USER" -a -n "$EXTRACT_JOB" -h -t PD 2>/dev/null | wc -l | awk '{print $1}')
    if [ "$PENDING" -gt 0 ]; then
        echo " ACTIVE:    No batch running (${PENDING} queued)"
    else
        echo " ACTIVE:    No batches running or queued"
    fi
fi

# 3. Extraction count
EXTRACTED=$(find "${OUTPUT_DIR}/" -name "*.json" -type f 2>/dev/null | wc -l | awk '{print $1}')

PERCENT=$(awk "BEGIN { printf \"%.2f\", ($EXTRACTED / $TOTAL_IMAGES) * 100 }")
BAR_WIDTH=24
FILLED=$(awk "BEGIN { printf \"%d\", ($EXTRACTED / $TOTAL_IMAGES) * $BAR_WIDTH }")
EMPTY=$((BAR_WIDTH - FILLED))
BAR=$(printf "%${FILLED}s" | tr ' ' '#')
BAR_EMPTY=$(printf "%${EMPTY}s" | tr ' ' '-')
[ "$FILLED" -eq 0 ] && BAR=""
[ "$EMPTY" -eq 0 ] && BAR_EMPTY=""

echo " EXTRACTED: $(printf "%'d" "$EXTRACTED") / $(printf "%'d" "$TOTAL_IMAGES")"
echo " PROGRESS:  [${BAR}${BAR_EMPTY}] ${PERCENT}%"

# 4. Failure count
TOTAL_FAILURES=$(find "${OUTPUT_DIR}/" -name "failed_cards_${MODEL_NAME}.txt" -exec cat {} + 2>/dev/null | wc -l | awk '{print $1}')
[ -z "$TOTAL_FAILURES" ] && TOTAL_FAILURES=0
if [ "$TOTAL_FAILURES" -gt 0 ]; then
    echo " FAILED:    ${TOTAL_FAILURES} failed extractions"
else
    echo " FAILED:    0 failures"
fi

echo ""
echo "=========================================================="
echo "Tip: watch -n 60 ${CODE_DIR}/scripts/check_progress.sh"
