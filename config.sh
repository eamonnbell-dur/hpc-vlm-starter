#!/bin/bash
# config.sh — Central configuration for the HPC VLM extraction pipeline.
# Source this file in all scripts: source "$(dirname "$0")/../config.sh"
#
# Edit the values below for your project. Everything else reads from here.

# ── Slurm Account ──
SLURM_ACCOUNT="MyAllocation"            # Your HPC allocation name

# ── Paths ──
PROJECT_DIR="/project/${SLURM_ACCOUNT}"
IMAGE_DIR="${PROJECT_DIR}/images"        # Where your scanned images live
OUTPUT_DIR="${PROJECT_DIR}/outputs"
LOG_DIR="${PROJECT_DIR}/logs"
MODEL_DIR="${PROJECT_DIR}/models"
CODE_DIR="${PROJECT_DIR}/code"

# ── Model ──
MODEL_PATH="${MODEL_DIR}/qwen2.5-vl-72b"          # Path to model weights
MODEL_NAME="my-extractor"                          # Served model name (your choice)
CONTAINER_PATH="${MODEL_DIR}/container/vllm_latest.sif"  # Apptainer/Singularity image

# ── GPU Configuration ──
GPU_COUNT=4                   # Total GPUs for the server
GPU_TYPE="a100"               # GPU type available on your cluster
GPU_CONSTRAINT="a100_80gb"    # Slurm constraint (remove if not needed)
TENSOR_PARALLEL=2             # Split model weights across N GPUs
PIPELINE_PARALLEL=2           # Split model layers across N GPU groups
SERVER_PORT=8000
SERVER_MEM="400G"             # Memory for the server node
SERVER_CPUS=32
SERVER_TIME="3-00:00:00"      # Max server uptime (3 days)

# ── Extraction ──
EXTRACTION_MODE="one_pass"    # "one_pass" or "two_pass"
PROMPT_FILE="${CODE_DIR}/prompts/my_prompt.txt"          # Your extraction prompt
PROMPT_FILE_PASS_B="${CODE_DIR}/prompts/my_prompt_pass_b.txt"  # (two_pass only) structuring prompt
WORKERS=32                    # Concurrent API requests per batch job
IMAGE_PATTERN="*.jpg"         # Glob pattern for your image files
MAX_TOKENS=1024
TEMPERATURE=0.0

# ── Batch Worker Resources ──
BATCH_MEM="32G"
BATCH_CPUS=8
BATCH_TIME="2-00:00:00"

# ── Retry Sweep ──
RETRY_WORKERS=8
RETRY_MEM="12G"
RETRY_TIME="12:00:00"

# ── Dataset ──
TOTAL_IMAGES=0                # Set this after running chunk_dataset.sh (it will update it)
BATCH_SIZE=100000             # Images per batch directory
