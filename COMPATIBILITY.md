# Cluster Compatibility Guide

This guide helps you assess whether your institution's HPC cluster can run this pipeline before you invest time in setup. It covers GPU requirements, VRAM thresholds, quantization options for smaller clusters, and job scheduler compatibility.

If you are unsure about any of these, your research computing help desk can confirm GPU generation, VRAM per card, and scheduler type in a single email.

---

## A Note on the Hardware Moment We're In

If your institution's current GPU cluster feels underpowered for this kind of work, it may not be for long. Research computing infrastructure at major universities is in active transition to NVIDIA's Blackwell generation — and the implications for historians and archivists running VLM pipelines are significant.

The A100 (80 GB), which powers our production pipeline, has been the workhorse of academic AI research for the past four years. Running a 72B model on A100s requires 4 cards and careful parallelism configuration — tensor-parallel and pipeline-parallel settings that introduce real complexity. The Blackwell generation changes that calculus substantially:

- **NVIDIA B200** (192 GB HBM3e, ~4.5 petaFLOPS FP8): A single card fits a 72B model with room to spare. No parallelism required. Several major research universities — including UVA — are bringing B200 clusters online in 2026.
- **NVIDIA RTX Pro 6000 Blackwell** (96 GB GDDR7): A workstation-class Blackwell card already available at institutions including UNC and UMich. A 72B model fits across two cards; a 27B model fits on one.

The practical upshot: a pipeline that currently requires a 4-GPU A100 node running for 10 days to process 1.4 million documents will likely run on a single B200 node in roughly the same time, with simpler configuration. For collections in the tens of thousands, a single Blackwell-generation GPU could finish the job in hours.

If your cluster feels like it's at the edge of what's possible for this work right now, check with your research computing office about their hardware roadmap. The window between "this seems out of reach" and "this runs on a single node" is closing quickly.

---

## GPU Architecture and VRAM

vLLM requires NVIDIA GPUs with CUDA compute capability **sm_70 or higher** (Volta architecture, 2017 or newer). Older GPUs — including Kepler (K20, K80), Maxwell, and Pascal-generation cards — will not run vLLM regardless of VRAM.

To check what GPUs your cluster has:
```bash
sinfo -o "%n %G" | grep gpu
```

### VRAM by Model Size

| VRAM Available | Viable Models |
|----------------|---------------|
| < 16 GB | Not recommended |
| 16 GB (e.g. A2, T4) | 7B models only, no headroom |
| 40 GB (e.g. A100 40GB) | Up to 13B comfortably; 27B with quantization |
| 80 GB (e.g. A100 80GB) | Up to 27B; 72B with 2–4 GPUs |
| 80 GB × 4 | 72B models comfortably |

### Quantization for Smaller Clusters

If your cluster only has smaller or older GPUs, quantization can reduce VRAM requirements significantly — often cutting memory use roughly in half at modest accuracy cost. This is worth exploring for 7B and 13B models on 8–16 GB cards.

Add the `--quantization` flag to the `vllm serve` command in `slurm/start_server.slurm`:

```bash
vllm serve /path/to/model \
    --served-model-name my-extractor \
    --quantization awq \          # or gptq
    --dtype auto \
    --host 0.0.0.0 \
    --port 8000
```

AWQ and GPTQ quantized versions of popular models are available on HuggingFace (search for model names with `-AWQ` or `-GPTQ` suffixes).

---

## Job Scheduler

The Slurm scripts in this kit (`slurm/*.slurm`) use `sbatch`, `squeue`, and `#SBATCH` directives and are specific to **Slurm**. If your cluster uses a different scheduler, the scripts will need to be adapted:

| Scheduler | Used At | Adaptation Needed |
|-----------|---------|-------------------|
| **Slurm** | Most major research universities | None — works as-is |
| **PBS/Torque** | Some older clusters | Replace `#SBATCH` with `#PBS` directives |
| **LSF** | Some HPC centers | Replace with `#BSUB` directives |
| **SGE/UGE** | Some departmental clusters | Replace with `#$ -` directives |
| **Scyld/proprietary** | Some smaller institutional clusters | Significant adaptation required |

The Python extraction scripts — `scripts/extract_one.py` and `scripts/batch_extract.py` — are scheduler-agnostic and will work on any system. Only the job submission wrappers need to change.

---

## Adapting the Scripts for Your Cluster

Even when your cluster meets the hardware requirements, the default scripts may need small adjustments to fit your site's policies. These are the most common issues encountered when deploying on clusters other than UVA Rivanna.

### Home directory and scratch space

`slurm/start_server.slurm` uses `--home "${FAKEHOME_DIR}"` to redirect Apptainer's home directory away from your real `$HOME` (which is often quota-constrained on HPC clusters). By default, `FAKEHOME_DIR` in `config.sh` points to `/scratch/${USER}/fakehome`.

If your cluster does not have a `/scratch` filesystem or you do not have write access there, change `FAKEHOME_DIR` to a directory within your project allocation:

```bash
# in config.sh
FAKEHOME_DIR="${PROJECT_DIR}/fakehome"
```

Create the directory before submitting your first job:

```bash
mkdir -p "${PROJECT_DIR}/fakehome/.cache/huggingface"
```

### Account (`-A`) and partition flags

The SLURM scripts include `#SBATCH -A ${SLURM_ACCOUNT}` and partition directives (`--partition=gpu`, `--partition=standard`). These work on clusters that use account-based billing and named partitions — but some institutions do not require or allow them.

If you receive a permissions error when submitting, try removing the `#SBATCH -A` line from the relevant script. If partition errors occur for CPU-only jobs (`run_batch.slurm`, `retry_failed.slurm`), try removing `--partition=standard` — many schedulers assign a default partition automatically for non-GPU jobs.

### HuggingFace offline mode

`HF_OFFLINE=1` in `config.sh` (the default) sets `TRANSFORMERS_OFFLINE=1` and `HF_HUB_OFFLINE=1` inside the container, preventing vLLM from attempting to contact HuggingFace Hub at startup. This is almost always correct when the model is already downloaded to your cluster — and on clusters with restricted outbound network access, it prevents startup failures where vLLM times out trying to fetch model metadata.

If you intentionally want to allow network access (e.g., to pull a model update), set `HF_OFFLINE=0` in `config.sh`.

### Context window override (`--max-model-len`)

Some large models cannot be loaded at their full default context window on smaller GPU configurations — the KV cache alone can exhaust available VRAM. If vLLM reports an OOM error at startup, set `MAX_MODEL_LEN` in `config.sh`:

```bash
MAX_MODEL_LEN=82224   # reduce until model loads; trade-off is shorter max input length
```

Leave `MAX_MODEL_LEN` empty (the default) to use the model's built-in context window.

---

## Examples: Smaller Institutional Clusters

Not all university clusters are large research computing facilities. Departmental and teaching clusters at smaller institutions may have significant constraints:

**JMU (NVIDIA A2, 16 GB VRAM, Slurm)**
The scripts will run, but only a 7B model fits. Expect slower throughput and less headroom for concurrent requests. Reduce `WORKERS` in `config.sh` to 4–8. Quantization may help.

**WMU Thor (NVIDIA K20, 5 GB VRAM, Scyld scheduler)**
This cluster is not compatible with vLLM. The K20 is a Kepler-generation GPU (sm_35), below the sm_70 requirement. The scheduler is also not Slurm. This pipeline cannot run on this infrastructure without a significant hardware upgrade.

If you are at a smaller institution with limited GPU resources, consider:
- Applying for an XSEDE/ACCESS allocation — national HPC resources available to researchers at any US institution
- Collaborating with a larger research university that has more capable infrastructure
- Contacting your research computing office about GPU upgrade plans or cloud burst options

---

## When a Laptop Beats the Cluster

If your institutional cluster has older GPUs, insufficient VRAM, or a non-Slurm scheduler — or if your collection is relatively small — a modern laptop may genuinely be the better choice.

Apple Silicon Macs (M4, M4 Max, M5, and later) use a unified memory architecture where CPU and GPU share the same memory pool. A MacBook Pro with 64 GB of unified memory can run a 27B model entirely in RAM; 128 GB opens up larger models. There is no separate VRAM constraint. Critically, both [Ollama](https://ollama.com) and [LM Studio](https://lmstudio.ai) — free, easy-to-install local model runners — expose an **OpenAI-compatible API endpoint**, which means `batch_extract.py` works without a single script change. Just point it at `http://localhost:11434/v1/chat/completions` (Ollama) or `http://localhost:1234/v1/chat/completions` (LM Studio) instead of your cluster.

### When local is the right call

- **Collection under ~5,000 images**: Queue wait time on a small cluster likely exceeds local processing time
- **Incompatible cluster infrastructure**: Older GPUs, wrong scheduler, or no GPU nodes at all
- **Privacy-sensitive materials**: Data never leaves your machine — no institutional network, no shared storage
- **Iterating on your prompt**: Much faster to test and refine locally before committing to a cluster run
- **No HPC allocation yet**: Start processing immediately while paperwork clears

### Rough throughput on Apple Silicon

| Hardware | Model | Approx. Throughput |
|----------|-------|--------------------|
| M4 Pro, 48 GB | 7B | ~8–12 images/min |
| M4 Max, 64 GB | 27B | ~2–4 images/min |
| M5, 128 GB | 27B | ~4–6 images/min |

At 3 images/minute on a 27B model, 5,000 images completes overnight (~28 hours). For 50,000 images, the cluster becomes the better tool.

### Getting started with Ollama

```bash
# Install Ollama (Mac/Linux)
curl -fsSL https://ollama.com/install.sh | sh

# Pull a vision-capable model
ollama pull qwen2.5vl:7b      # 7B — fast, fits 16 GB+
ollama pull qwen2.5vl:32b     # 32B — better quality, needs 64 GB+

# Ollama serves on port 11434 by default
# Point batch_extract.py at it:
python scripts/batch_extract.py \
    --input-dir ./my_images/ \
    --output-dir ./outputs/ \
    --endpoint http://localhost:11434/v1/chat/completions \
    --model qwen2.5vl:7b \
    --prompt-file prompts/my_prompt.txt \
    --workers 2
```

Keep `--workers` low (2–4) on local runs — you are the only user, and the model is already saturating your hardware.

---

## Quick Checklist

Before starting setup, verify:

- [ ] Cluster uses Slurm (or you are prepared to adapt the scripts)
- [ ] GPUs are NVIDIA, Volta (2017) or newer (sm_70+)
- [ ] At least 16 GB VRAM available per GPU node
- [ ] Apptainer or Singularity available (`apptainer --version`)
- [ ] Python 3.9+ available via module system (`module avail python`)
- [ ] Sufficient project storage for model weights (14–150 GB depending on model) and output JSON files
