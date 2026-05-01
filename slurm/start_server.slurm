#!/bin/bash
# start_server.slurm — Launch a vLLM inference server on GPU nodes.
# Reads all configuration from config.sh.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

#SBATCH -A ${SLURM_ACCOUNT}
#SBATCH --time=${SERVER_TIME}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=${SERVER_CPUS}
#SBATCH --gres=gpu:${GPU_TYPE}:${GPU_COUNT}
#SBATCH --constraint=${GPU_CONSTRAINT}
#SBATCH --partition=gpu
#SBATCH --mem=${SERVER_MEM}
#SBATCH -J "vlm-server"
#SBATCH -o ${LOG_DIR}/vllm_server_%j.out
#SBATCH -e ${LOG_DIR}/vllm_server_%j.err

module purge
module load apptainer

mkdir -p "${LOG_DIR}"
mkdir -p "${FAKEHOME_DIR}/.cache/huggingface"
mkdir -p "${FAKEHOME_DIR}/.cache/vllm"

# Write node address so worker scripts can find the server
echo "${SLURMD_NODENAME}:${SERVER_PORT}" > "${LOG_DIR}/vllm_server_address.txt"
echo "Server starting on ${SLURMD_NODENAME}:${SERVER_PORT}"

# Optional: reduce context window to lower KV-cache VRAM usage
VLLM_EXTRA_ARGS=()
[ -n "${MAX_MODEL_LEN}" ] && VLLM_EXTRA_ARGS+=(--max-model-len "${MAX_MODEL_LEN}")

apptainer exec --nv \
    --home "${FAKEHOME_DIR}" \
    --bind "${PROJECT_DIR}:${PROJECT_DIR}" \
    --env XDG_CACHE_HOME="${FAKEHOME_DIR}/.cache" \
    --env HF_HOME="${FAKEHOME_DIR}/.cache/huggingface" \
    --env PYTHONNOUSERSITE=1 \
    --env VLLM_DO_NOT_TRACK=1 \
    --env TRANSFORMERS_OFFLINE="${HF_OFFLINE}" \
    --env HF_HUB_OFFLINE="${HF_OFFLINE}" \
    "${CONTAINER_PATH}" \
    vllm serve "${MODEL_PATH}" \
        --served-model-name "${MODEL_NAME}" \
        --tensor-parallel-size "${TENSOR_PARALLEL}" \
        --pipeline-parallel-size "${PIPELINE_PARALLEL}" \
        --dtype auto \
        --host 0.0.0.0 \
        --port "${SERVER_PORT}" \
        "${VLLM_EXTRA_ARGS[@]}"
