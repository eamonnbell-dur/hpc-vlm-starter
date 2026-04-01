# Cluster Compatibility Guide

This guide helps you assess whether your institution's HPC cluster can run this pipeline before you invest time in setup. It covers GPU requirements, VRAM thresholds, quantization options for smaller clusters, and job scheduler compatibility.

If you are unsure about any of these, your research computing help desk can confirm GPU generation, VRAM per card, and scheduler type in a single email.

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

## Quick Checklist

Before starting setup, verify:

- [ ] Cluster uses Slurm (or you are prepared to adapt the scripts)
- [ ] GPUs are NVIDIA, Volta (2017) or newer (sm_70+)
- [ ] At least 16 GB VRAM available per GPU node
- [ ] Apptainer or Singularity available (`apptainer --version`)
- [ ] Python 3.9+ available via module system (`module avail python`)
- [ ] Sufficient project storage for model weights (14–150 GB depending on model) and output JSON files
