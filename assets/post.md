# Post template — fill what you can, `unknown` for the rest

# Reddit Post Title: `<SHORT_LLM_NAME> - <quant, lower> - <Engine> - <~general-task TOK/s, rounded> - <GPUS>`

# TLDR

- General decode: `~NN tok/s @ 48k`

- Coding decode: `~NN tok/s @ 48k`

## Model
MODEL:\
QUANT:\
Fine Tuning:\
HF LINK: `https://huggingface.co/<org>/<repo>`  (a web-search match is printed with "(likely)")\
Warm TTFT:\
Warm TOK/s:\

## System
OS:\
GPU#0: `<GPU_TYPE> - <GPU_VRAM>`\
GPU#1:\
GPU#2:\
CPU:\
RAM:\

## Inference
ENGINE:\
ENGINE VERSION:\
DRAFTER:\
FLAGS:\

## Harness
Harness:\
Harness Tools:\

## Additional
Additional Notes (human): `<anything that would change a reader's conclusion>`\

## Time Results
Benchmark Start Time: `<UTC>`\
Benchmark End Time: `<UTC>`\
Total Time for Benchmark: `<seconds>`\

Every field line above ends with `\` — reddit renders a single newline as a space, and the backslash
is what makes each field its own line — except the last line of a block, which needs none.
Headings, the table and the list items break on their own.
The fenced `yaml` block below is always written to the saved post, and appears in the pasted text only
with `--yaml`. It stays plain — it is what makes posts searchable and what the history skill reads.

```yaml
schema: benchmarkllms/v2
```

Benchmarked with [BenchmarkLLMs](https://github.com/altmush/BenchmarkLLMs)
