## Post Title: fn-dual-designer

# TLDR

- General decode: ~59.5 tok/s @ 0k

## Model
MODEL: fn-dual-designer
QUANT: unknown
HF LINK: unknown
Prefill: see table
TOK/s Decode: see table
TTFT: see table

## System
OS: Bazzite
GPU#0: NVIDIA GeForce RTX 3060 - 12.0 GB
GPU#1: Tesla V100-SXM2-16GB - 16.0 GB
GPU#2: NVIDIA GeForce RTX 3060 - 12.0 GB
CPU: 12th Gen Intel(R) Core(TM) i5-12600K
RAM: 76.6 GB

## Inference
ENGINE: ollama  (identity guessed from endpoints — verify)
ENGINE VERSION: v262
ENGINE COMMIT: unknown
DRAFTER: unknown
FLAGS: unknown

## Harness
Harness: pi
Harness Tools: read bash edit write
Harness Commit: unknown

## Additional
Additional Notes (human): no engine dir passed, so the engine name below is a guess

```yaml
schema: benchmarkllms/v1
date: 2026-11-25
model: "fn-dual-designer"
quant: "unknown"
hf: "unknown"
engine: {name: ollama, version: "v262", commit: "unknown", remote: "unknown", flags: "unknown", drafter: "unknown"} identity_source: "probe"}
harness: {name: pi, version: "unknown", commit: "unknown", tools: ["read", "bash", "edit", "write"], model_alias: "unknown", endpoint: "http://127.0.0.1:4444", self_contention: true, identity_source: "config"}
os: "Bazzite"
cpu: "12th Gen Intel(R) Core(TM) i5-12600K"
ram: "76.6 GB"
gpus: [{"id": 0, "model": "NVIDIA GeForce RTX 3060", "vram_gb": 12.0, "uuid": "GPU-87c6", "driver": "580.196.07", "source": "nvidia-smi"}, {"id": 1, "model": "Tesla V100-SXM2-16GB", "vram_gb": 16.0, "uuid": "GPU-21fd", "driver": "580.196.07", "source": "nvidia-smi"}, {"id": 2, "model": "NVIDIA GeForce RTX 3060", "vram_gb": 12.0, "uuid": "GPU-76d2", "driver": "580.196.07", "source": "nvidia-smi"}]
measurement: {source: client, batch: 1, prefix_cache: off, temperature: 0, seed: 1234, n: 1, statistic: median, warmup: 0, max_tokens: 16}
model_max_context: 65536
ladder: [0]
runs:
  - task: general
    seed_sha256: 0276cc01a1ad
    points:
      - {"target_ctx": 0, "actual_ctx": 123, "prefill_tps": 65.4, "decode_tps": 59.5, "ttft_s": 1.9, "total_s": 2.1, "out_tokens": 16, "ttft_stdev_s": 0, "total_stdev_s": 0, "runs": 1, "source": "engine", "draft_tokens": 12, "acceptance_rate": 0.75}
quality: {task: general, pass: 0, of: 0}
notes: "no engine dir passed, so the engine name below is a guess"
```
