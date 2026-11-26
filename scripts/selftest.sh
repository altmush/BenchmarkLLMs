#!/usr/bin/env bash
# Self-check for the four bits a wrong answer would silently publish: filename -> quant/tuning, the
# llama-swap alias lookup, the saved-answers store, and the history table. No network, no engine.
set -u
PY="$(cd "$(dirname "$0")" && pwd)/tool.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }
strip() { sed 's/[[:space:]]*$//'; }   # the post ends the lines a human reads with a markdown hard break
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
printf '%s\n' '#!/bin/bash' 'exec llama-server --model ~/models/Foo-Bar-Q4_K_M.gguf' '# --model ~/models/Yesterday-Q2_S.gguf' > "$T/launch.sh"
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
check "post header prints the median at the ladder point, per task" "Warm TOK/s: 108.5\\" \
      "$(python3 "$PY" post "$T2/meta" "$T2/runs" | grep -F 'Warm TOK/s' | strip)"
check "and the median TTFT" "Warm TTFT: 0.4 s\\" \
      "$(python3 "$PY" post "$T2/meta" "$T2/runs" | grep -F 'Warm TTFT' | strip)"
check "the post header labels the field it searched the web for" "HF LINK: https://huggingface.co/some/repo  (likely)\\" \
      "$(python3 "$PY" post "$T2/meta" /dev/null | grep -F 'HF LINK' | strip)"
check "a field it did not guess is not labelled" "HF LINK: https://huggingface.co/some/repo\\" \
      "$(sed -i 's/^hf_source.*/hf_source\tpost-verified/' "$T2/meta"; python3 "$PY" post "$T2/meta" /dev/null | grep -F 'HF LINK' | strip)"
rm -rf "$T2"
if curl -fsS --max-time 20 --retry 3 'https://huggingface.co/api/models?search=Qwen2.5-0.5B&limit=1' >/dev/null 2>&1; then
  # the org inside a filename is the strongest clue there is: reading it as an author filter is what
  # puts the real repo at the top, where a plain name search put a stranger's repo first
  check "and reads the org out of the filename, not just the model name" \
        "https://huggingface.co/SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF" \
        "$(python3 "$PY" hfsearch Swift-Qwen3.8-Flash-Next-IQ3_XXS-abliterated-SC117.gguf | sed -n 1p | cut -f1)"
  check "and never invents a repo id when the search finds nothing" "" "$(python3 "$PY" hfsearch nosuchmodel-xyzzy-9999.gguf)"
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
check "the reply ends with the timings and the open questions" "Total Time for Benchmark: 668s\\" \
      "$(python3 "$PY" post "$T3/meta" "$T3/runs" reply | grep -m1 -F 'Total Time')"
check "the reply fences the post so it survives copy-paste" '````markdown' \
      "$(python3 "$PY" post "$T3/meta" "$T3/runs" reply | grep -m1 -F '````markdown')"
check "and a field nobody confirmed is asked, not printed as a fact" "- engine: unknown (source: unknown)" \
      "$(python3 "$PY" post "$T3/meta" "$T3/runs" reply | grep -m1 -F -- '- engine:')"
rm -rf "$T3"
T4=$(mktemp -d)
{
  printf 'model\tQwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_XXS\nquant\tIQ3_XXS\nengine\tstrata\n'
  printf 'gpus\t[{"id": 0, "model": "Tesla V100-SXM2-16GB", "vram_gb": 16.0}, {"id": 1, "model": "NVIDIA GeForce RTX 3060", "vram_gb": 12.0}, {"id": 2, "model": "NVIDIA GeForce RTX 3060", "vram_gb": 12.0}]\n'
} > "$T4/meta"
for n in 1 2 3; do printf 'coding\t49152\taaa\tM\tE\t43664\t256\t0.11\t2.74\t%s\t200\t0\t0\t150\t2590\n' "$n"; done > "$T4/runs"
for n in 1 2 3; do printf 'general\t49152\tbbb\tM\tE\t43647\t256\t0.10\t2.87\t%s\t200\t0\t0\t120\t2750\n' "$n"; done >> "$T4/runs"
check "the title is short name, quant, engine, median tok/s and cards — not the whole filename" \
      "# Reddit Post Title: Qwen3.8 - iq3_xxs - Strata - ~93 TOK/s - V100(16gb) + 2x3060s(12gb)" \
      "$(python3 "$PY" post "$T4/meta" "$T4/runs" | sed -n 1p | strip)"
check "so a line a human reads really breaks on reddit" "MODEL: Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_XXS\\" \
      "$(python3 "$PY" post "$T4/meta" "$T4/runs" | grep -m1 -F 'MODEL:')"
check "and the fenced yaml block stays plain for the machine" "" \
      "$(python3 "$PY" post "$T4/meta" "$T4/runs" | awk '/^```yaml/{f=1;next} f&&/  $/')"
printf 'model\tModelA\nnotes\t\n' > "$T/empty-meta"
check "and the human's notes field is left blank" "Additional Notes (human): \\" \
      "$(python3 "$PY" post "$T/empty-meta" /dev/null | grep -F 'Additional Notes' | strip)"
rm -rf "$T4"
exit $fail
