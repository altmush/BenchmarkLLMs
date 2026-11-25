## Post Title: Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_XXS iq3_xxs

# TLDR

- General decode: ~78.2 tok/s @ 48k

- Coding decode: ~98.4 tok/s @ 48k

## Model
MODEL: Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_XXS
QUANT: iq3_xxs
Fine Tuning: Swift GSQ-RCO abliterated
HF LINK: https://huggingface.co/SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF/tree/main/IQ3_XXS
Warm TTFT: 0.1 s
Warm TOK/s: 87.6

## System
OS: Bazzite
GPU#0: NVIDIA GeForce RTX 3060 - 12.0 GB
GPU#1: Tesla V100-SXM2-16GB - 16.0 GB
GPU#2: NVIDIA GeForce RTX 3060 - 12.0 GB
CPU: 12th Gen Intel(R) Core(TM) i5-12600K
RAM: 76.6 GB

## Inference
ENGINE: strata
ENGINE VERSION: 0.1.66
ENGINE COMMIT: unknown
DRAFTER: unknown
FLAGS: unknown

## Harness
Harness: pi
Harness Tools: read bash edit write codemode
Harness Commit: unknown

## Additional
Additional Notes (human): unknown


## Results

| task | ladder | actual ctx | prefill tok/s | decode tok/s | TTFT s | total s | stdev s | runs | source |
|---|---|---|---|---|---|---|---|---|---|
| coding | 49152 | 43664 | 305129.3 | 98.4 | 0.1 | 2.7 | 0.0 | 3 | engine draft 173, accepted 0.876 |
| general | 49152 | 43647 | 298135.2 | 78.2 | 0.1 | 3.4 | 0.0 | 3 | engine draft 151, accepted 0.808 |

## Time Results
Benchmark Start Time: 2026-11-25T20:12:20+0000
Benchmark End Time: 2026-11-25T20:12:48Z
Total Time for Benchmark: 28s

```yaml
schema: benchmarkllms/v2
date: 2026-11-25
model: "Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_XXS"
model_source: "flag"
quant: "iq3_xxs"
fine_tuning: "Swift GSQ-RCO abliterated"
hf: "https://huggingface.co/SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF/tree/main/IQ3_XXS"
engine: {name: strata, version: "0.1.66", commit: "unknown", remote: "unknown", flags: "unknown", drafter: "unknown"} identity_source: "flag"}
harness: {name: pi, version: "unknown", commit: "unknown", tools: ["read", "bash", "edit", "write", "codemode"], model_alias: "fn-dual-designer", endpoint: "4444 (host redacted)", self_contention: true, identity_source: "config"}
os: "Bazzite"
cpu: "12th Gen Intel(R) Core(TM) i5-12600K"
ram: "76.6 GB"
gpus: [{"id": 0, "model": "NVIDIA GeForce RTX 3060", "vram_gb": 12.0, "uuid": "GPU-87c6", "driver": "580.196.07", "source": "nvidia-smi"}, {"id": 1, "model": "Tesla V100-SXM2-16GB", "vram_gb": 16.0, "uuid": "GPU-21fd", "driver": "580.196.07", "source": "nvidia-smi"}, {"id": 2, "model": "NVIDIA GeForce RTX 3060", "vram_gb": 12.0, "uuid": "GPU-76d2", "driver": "580.196.07", "source": "nvidia-smi"}]
measurement: {source: client, batch: 1, prefix_cache: off, temperature: 0, seed: 1234, n: 3, statistic: median, warmup: 1, max_tokens: 256}
model_max_context: 204800
ladder: [49152]
bench_start: "2026-11-25T20:12:20+0000"
bench_end: "2026-11-25T20:12:48Z"
total_time_s: 28s
runs:
  - task: coding
    seed_sha256: 09d5354dd113
    points:
      - {"target_ctx": 49152, "actual_ctx": 43664, "prefill_tps": 305129.3, "decode_tps": 98.4, "ttft_s": 0.1, "total_s": 2.7, "out_tokens": 256, "ttft_stdev_s": 0.0, "total_stdev_s": 0.22, "runs": 3, "source": "engine", "draft_tokens": 173, "acceptance_rate": 0.876}
  - task: general
    seed_sha256: 0276cc01a1ad
    points:
      - {"target_ctx": 49152, "actual_ctx": 43647, "prefill_tps": 298135.2, "decode_tps": 78.2, "ttft_s": 0.1, "total_s": 3.4, "out_tokens": 256, "ttft_stdev_s": 0.0, "total_stdev_s": 0.14, "runs": 3, "source": "engine", "draft_tokens": 151, "acceptance_rate": 0.808}
quality: {task: general, pass: 0, of: 0}
notes: "unknown"
```

Benchmarked with [BenchmarkLLMs](https://github.com/altmush/BenchmarkLLMs)
