#!/bin/bash
# chunk_dataset.sh — Split a directory of images into numbered batch directories.
# This makes it possible to process large collections in sequential Slurm jobs
# with dependency chaining and per-batch failure tracking.
#
# Usage: ./scripts/chunk_dataset.sh
#
# Reads IMAGE_DIR, BATCH_SIZE, and IMAGE_PATTERN from config.sh.
# Creates batch_01/, batch_02/, ... inside IMAGE_DIR with symlinks to originals.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

cd "${IMAGE_DIR}" || { echo "ERROR: IMAGE_DIR not found: ${IMAGE_DIR}"; exit 1; }

echo "Scanning for images matching '${IMAGE_PATTERN}'..."
mapfile -t ALL_IMAGES < <(find . -maxdepth 1 -name "${IMAGE_PATTERN}" -type f | sort)

TOTAL=${#ALL_IMAGES[@]}
if [ "$TOTAL" -eq 0 ]; then
    echo "No images found matching '${IMAGE_PATTERN}' in ${IMAGE_DIR}"
    exit 1
fi

NUM_BATCHES=$(( (TOTAL + BATCH_SIZE - 1) / BATCH_SIZE ))

echo "Found ${TOTAL} images. Splitting into ${NUM_BATCHES} batches of up to ${BATCH_SIZE}."

BATCH_NUM=1
COUNT=0

for img in "${ALL_IMAGES[@]}"; do
    if [ "$COUNT" -eq 0 ]; then
        BATCH_DIR=$(printf "batch_%02d" "$BATCH_NUM")
        mkdir -p "$BATCH_DIR"
        echo "  Creating ${BATCH_DIR}..."
    fi

    # Symlink instead of copy to save disk space
    ln -sf "$(pwd)/${img}" "${BATCH_DIR}/$(basename "$img")"

    COUNT=$((COUNT + 1))

    if [ "$COUNT" -ge "$BATCH_SIZE" ]; then
        echo "    -> ${COUNT} images"
        BATCH_NUM=$((BATCH_NUM + 1))
        COUNT=0
    fi
done

# Report final partial batch
if [ "$COUNT" -gt 0 ]; then
    echo "    -> ${COUNT} images"
fi

echo ""
echo "Done. ${NUM_BATCHES} batch directories created in ${IMAGE_DIR}."
echo ""
echo "Update config.sh with:"
echo "  TOTAL_IMAGES=${TOTAL}"
echo ""
echo "Then submit the pipeline:"
echo "  ./scripts/submit_pipeline.sh 1 ${NUM_BATCHES}"
