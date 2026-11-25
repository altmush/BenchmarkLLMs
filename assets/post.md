# Post template — fill what you can, `unknown` for the rest

# Reddit Post Title: `<SHORT_LLM_NAME> - <QUANT> - <ENGINE> - <~WARM_TOKS> - <GPUS>`

## Model
MODEL:
QUANT:
Fine Tuning:
HF LINK: `https://huggingface.co/<org>/<repo>`  (a web-search match is printed with "(likely)")
Warm TTFT:
Warm TOK/s:

## System
OS:
GPU#0: `<GPU_TYPE> - <GPU_VRAM>`
GPU#1:
GPU#2:
CPU:
RAM:

## Inference
ENGINE:
ENGINE VERSION:
DRAFTER:
FLAGS:

## Harness
Harness:
Harness Tools:

## Additional
Additional Notes (human): `<anything that would change a reader's conclusion>`

## Time Results
Benchmark Start Time: `<UTC>`
Benchmark End Time: `<UTC>`
Total Time for Benchmark: `<seconds>`

The fenced `yaml` block below is part of the post. Leave it in — it is what makes posts
searchable, and the skill writes it for you.

```yaml
schema: benchmarkllms/v2
```

Benchmarked with [BenchmarkLLMs](https://github.com/altmush/BenchmarkLLMs)
