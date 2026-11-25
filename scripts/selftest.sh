#!/usr/bin/env bash
# Self-check for the four bits a wrong answer would silently publish: filename -> quant/tuning, the
# llama-swap alias lookup, the saved-answers store, and the history table. No network, no engine.
set -u
PY="$(cd "$(dirname "$0")" && pwd)/tool.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }
ni() { python3 "$PY" nameinfo "$1" | sed -n "s/^$2\t//p"; }

check "quant in the middle of a long name" "IQ3_XXS" "$(ni Swift-Qwen3.8-Flash-Next-IQ3_XXS-abliterated-SC117.gguf quant)"
check "tuner tokens from the name"         "Swift abliterated" "$(ni Swift-Qwen3.8-Flash-Next-IQ3_XXS-abliterated-SC117.gguf tuning)"
check "quant at the end (old shape)"       "Q4_K_XL" "$(ni gemma-4-31B-it-qat-UD-Q4_K_XL.gguf quant)"
check "a model name is not a tuner"        "" "$(ni gemma-4-31B-it-qat-UD-Q4_K_XL.gguf tuning)"

cat > "$T/x.yaml" <<EOF
models:
  "nick":
    cmd: $T/launch.sh
EOF
printf '%s\n' '#!/bin/bash' 'exec llama-server --model /mnt/ai/llms/Foo-Bar-Q4_K_M.gguf' '# --model /mnt/ai/llms/Yesterday-Q2_S.gguf' > "$T/launch.sh"
check "a selector that names its file resolves" "Foo-Bar-Q4_K_M" "$(python3 "$PY" swap "$T/x.yaml" nick)"
check "a selector that does not is a question"  "" "$(python3 "$PY" swap "$T/x.yaml" othername)"

python3 "$PY" profile set "$T/p.json" "host:1 nick" real_name=Foo-Bar-Q4_K_M quant=unknown > /dev/null
check "saved answers come back"   "Foo-Bar-Q4_K_M" "$(python3 "$PY" profile get "$T/p.json" "host:1 nick" | sed -n 's/^real_name\t//p')"
check "unknown is never stored"   "" "$(python3 "$PY" profile get "$T/p.json" "host:1 nick" | sed -n 's/^quant\t//p')"

cat > "$T/a.md" <<'EOF'
```yaml
date: 2026-11-01
model: "ModelA"
quant: "q4_k_m"
engine: {name: llama.cpp, version: "b1", commit: "unknown", remote: "unknown", flags: "unknown", drafter: "unknown"} identity_source: "flag"}
measurement: {source: client, batch: 1, prefix_cache: off, temperature: 0, seed: 1234, n: 3, statistic: median, warmup: 1, max_tokens: 256}
runs:
  - task: general
    seed_sha256: aaa
    points:
      - {"target_ctx": 0, "decode_tps": 999.9, "ttft_s": 0.1}
      - {"target_ctx": 16384, "decode_tps": 888.8, "ttft_s": 0.2}
      - {"target_ctx": 49152, "decode_tps": 111.1, "ttft_s": 3.3}
```
EOF
cat > "$T/b.md" <<'EOF'
```yaml
date: 2026-11-02
model: "ModelB"
quant: "q8_0"
engine: {name: vllm, version: "0.9", commit: "unknown", remote: "unknown", flags: "unknown", drafter: "unknown"} identity_source: "flag"}
measurement: {source: client, batch: 1, prefix_cache: off, temperature: 0, seed: 1234, n: 3, statistic: median, warmup: 1, max_tokens: 256}
runs:
  - task: general
    seed_sha256: bbb
    points:
      - {"target_ctx": 49152, "decode_tps": 222.2, "ttft_s": 1.5}
      - {target_ctx: 65536, error: curl-fail, runs: 0}
```
EOF
check "history fills both columns from the right points" \
      "| ModelA | q4_k_m | llama.cpp | b1 | 999.9 | 0.1 | 111.1 | 3.3 | 2026-11-01 |" \
      "$(python3 "$(dirname "$0")/history.py" "$T" | grep -m1 -F 'ModelA |')"
check "a post with only the ladder point has no cold number" \
      "| ModelB | q8_0 | vllm | 0.9 | - | - | 222.2 | 1.5 | 2026-11-02 |" \
      "$(python3 "$(dirname "$0")/history.py" "$T" | grep -m1 -F 'ModelB |')"
check "history sorts highest tok/s first" "ModelA" \
      "$(python3 "$(dirname "$0")/history.py" "$T" | sed -n '/^| LLM/,/^$/p' | sed -n '3p' | cut -d'|' -f2 | tr -d ' ')"

T2=$(mktemp -d)
{
  for k in model model_source quant quant_source fine_tuning fine_tuning_source hf hf_source date schema \
           os cpu ram gpus engine engine_source engine_version engine_commit drafter flags \
           harness_name harness_source harness_tools harness_commit notes; do
    printf '%s\tunknown\n' "$k"
  done
  printf 'schema\tbenchmarkllms/v2\nmodel\tModelA\nhf\thttps://huggingface.co/some/repo\nhf_source\tsearch\ngpus\t[]\n'
} > "$T2/meta"
for n in 1 2 3; do
  printf 'coding\t49152\taaa\tM\tE\t48000\t256\t%s\t%s\t%s\t200\t0\t0\t400\t%s\n' \
         "$((1000 + n * 100))" "$((2560 - n * 100))" "$n" "$((2560 - n * 100))" >> "$T2/runs"
done
check "post header prints the median at the ladder point, per task" "Warm TOK/s: 108.5" \
      "$(python3 "$PY" post "$T2/meta" "$T2/runs" | grep -F 'Warm TOK/s')"
check "and the median TTFT" "Warm TTFT: 0.4 s" \
      "$(python3 "$PY" post "$T2/meta" "$T2/runs" | grep -F 'Warm TTFT')"
check "the post header labels the field it searched the web for" "HF LINK: https://huggingface.co/some/repo  (likely)" \
      "$(python3 "$PY" post "$T2/meta" /dev/null | grep -F 'HF LINK')"
check "a field it did not guess is not labelled" "HF LINK: https://huggingface.co/some/repo" \
      "$(sed -i 's/^hf_source.*/hf_source\tpost-verified/' "$T2/meta"; python3 "$PY" post "$T2/meta" /dev/null | grep -F 'HF LINK')"
rm -rf "$T2"
if curl -fsS --max-time 5 'https://huggingface.co/api/models?search=Qwen2.5-0.5B&limit=1' >/dev/null 2>&1; then
  check "the web search keeps the repo's own spelling, and calls a near miss a guess" \
        "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct	likely" "$(python3 "$PY" hfsearch Qwen2.5-0.5B.gguf | sed -n 1p)"
  check "and labels a match that only looks like it" \
        "https://huggingface.co/pegasus912/gemma-4-31b-it-qat-heretic-ud-q4-k-xl	likely" \
        "$(python3 "$PY" hfsearch gemma-4-31B-it-qat-heretic-UD-Q4_K_XL.gguf | sed -n 1p)"
else
  echo "skip  the web search tests (no network)"
fi
T3=$(mktemp -d)
{
  for k in model model_source quant fine_tuning hf hf_source os cpu ram gpus engine engine_source \
          engine_version harness_name harness_tools bench_start bench_end total_time_s; do
    printf '%s\tunknown\n' "$k"
  done
  printf 'model\tsuccess\nhf_source\tpost-verified\nbench_start\t2026-11-25T14:41:02Z\nbench_end\t2026-11-25T14:52:10Z\ntotal_time_s\t668s\n' >> "$T3/meta"
  printf 'coding\t49152\taaa\tM\tE\t48000\t256\t1100\t2327\t1\t200\t0\t0\t400\t2200\n' >> "$T3/runs"
} > "$T3/meta"
check "the reply ends with the timings and the open questions" "Total Time for Benchmark: 668s" \
      "$(python3 "$PY" post "$T3/meta" "$T3/runs" reply | grep -m1 -F 'Total Time')"
check "the reply fences the post so it survives copy-paste" '````markdown' \
      "$(python3 "$PY" post "$T3/meta" "$T3/runs" reply | grep -m1 -F '````markdown')"
check "and a field nobody confirmed is asked, not printed as a fact" "- engine: unknown (source: unknown)" \
      "$(python3 "$PY" post "$T3/meta" "$T3/runs" reply | grep -m1 -F -- '- engine:')"
rm -rf "$T3"
