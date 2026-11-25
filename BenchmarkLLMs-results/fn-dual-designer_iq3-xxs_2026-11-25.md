## Post Title: fn-dual-designer

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
ENGINE: ollama
ENGINE VERSION: v262
DRAFTER: unknown
FLAGS: unknown

## Harness
Harness: pi
Harness Tools: read bash edit write

## Additional
NOTES: unknown

```yaml
schema: benchmarkllms/v1
date: 2026-11-25
model: "fn-dual-designer"
quant: "unknown"
hf: "unknown"
engine: {name: ollama, version: "v262", flags: "unknown", drafter: "unknown"}
harness: {name: pi, tools: ["read", "bash", "edit", "write"], model_alias: "fn-dual-designer", endpoint: "http://192.168.1.42:4444"}
os: "Bazzite"
cpu: "12th Gen Intel(R) Core(TM) i5-12600K"
ram: "76.6 GB"
gpus: [{"id": 0, "model": "NVIDIA GeForce RTX 3060", "vram_gb": 12.0, "uuid": "GPU-87c60449-68a0-84f2-e064-a589c6d98e31", "driver": "580.196.07", "source": "nvidia-smi"}, {"id": 1, "model": "Tesla V100-SXM2-16GB", "vram_gb": 16.0, "uuid": "GPU-21fd35c1-2672-2c41-0797-0eed49dab1ba", "driver": "580.196.07", "source": "nvidia-smi"}, {"id": 2, "model": "NVIDIA GeForce RTX 3060", "vram_gb": 12.0, "uuid": "GPU-76d2dc9e-724b-8cef-80c1-293d00f71de9", "driver": "580.196.07", "source": "nvidia-smi"}]
measurement: {source: client, batch: 1, prefix_cache: off, temperature: 0, seed: 1234, n: 3, statistic: median, warmup: 1, max_tokens: 256}
model_max_context: 204800
ladder: [0,16384,32768,49152,65536]
runs:
  - task: coding
    seed_sha256: 09d5354dd113
    points:
      - {"target_ctx": 0, "actual_ctx": 140, "prefill_tps": 1414.1, "decode_tps": 115.7, "ttft_s": 0.1, "total_s": 2.3, "out_tokens": 256, "ttft_stdev_s": 0.0, "total_stdev_s": 0.11, "runs": 3, "source": "engine", "draft_tokens": 192, "acceptance_rate": 0.859}
  - task: coding
    seed_sha256: 09d5354dd113
    points:
      - {"target_ctx": 16384, "actual_ctx": 14462, "prefill_tps": 120516.7, "decode_tps": 93.9, "ttft_s": 0.1, "total_s": 2.9, "out_tokens": 256, "ttft_stdev_s": 0.0, "total_stdev_s": 0.19, "runs": 3, "source": "engine", "draft_tokens": 176, "acceptance_rate": 0.796}
  - task: coding
    seed_sha256: 09d5354dd113
    points:
      - {target_ctx: 32768, error: curl-fail, runs: 0}
  - task: coding
    seed_sha256: 09d5354dd113
    points:
      - {target_ctx: 49152, error: curl-fail, runs: 0}
  - task: coding
    seed_sha256: 09d5354dd113
    points:
      - {target_ctx: 65536, error: curl-fail, runs: 0}
  - task: general
    seed_sha256: 0276cc01a1ad
    points:
      - {"target_ctx": 0, "actual_ctx": 123, "prefill_tps": 1215.4, "decode_tps": 91.8, "ttft_s": 0.1, "total_s": 2.9, "out_tokens": 256, "ttft_stdev_s": 0.0, "total_stdev_s": 0.15, "runs": 3, "source": "engine", "draft_tokens": 175, "acceptance_rate": 0.8}
  - task: general
    seed_sha256: 0276cc01a1ad
    points:
      - {"target_ctx": 16384, "actual_ctx": 14445, "prefill_tps": 119380.2, "decode_tps": 90.5, "ttft_s": 0.1, "total_s": 3.0, "out_tokens": 256, "ttft_stdev_s": 0.01, "total_stdev_s": 0.32, "runs": 3, "source": "engine", "draft_tokens": 151, "acceptance_rate": 0.808}
  - task: general
    seed_sha256: 0276cc01a1ad
    points:
      - {target_ctx: 32768, error: curl-fail, runs: 0}
  - task: general
    seed_sha256: 0276cc01a1ad
    points:
      - {target_ctx: 49152, error: curl-fail, runs: 0}
  - task: general
    seed_sha256: 0276cc01a1ad
    points:
      - {target_ctx: 65536, error: curl-fail, runs: 0}
quality: {task: general, pass: 0, of: 0}
notes: "unknown"
```
