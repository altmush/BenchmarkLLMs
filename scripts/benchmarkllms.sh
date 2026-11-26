#!/usr/bin/env bash
# Collects machine + engine facts and runs the context ladder, then prints a post.
# deps: bash, curl, python3. No sudo, no jq (used if present, never required).
# Never fails on a missing probe: every unknown fact is reported as "unknown".
#
# usage: benchmarkllms.sh [--endpoint URL] [--model ID] [--ladder 0,16384,...]
#        [--tasks general,coding] [--n 3] [--warmup 1] [--max-tokens 256]
#        [--temperature 0] [--seed 1234] [--mode engine|harness]
#        [--harness-name NAME] [--harness-tools "a b c"] [--harness-model-alias ALIAS]
#        [--out BenchmarkLLMs-results/FILE.md] [--no-bench]
#        [--ask] [--save-profile] [--profile FILE] [--real-name NAME] [--fine-tuning TAG]
#        [--swap-config FILE] [--model-dir DIR] [--engine-dir DIR] [--harness-dir DIR]
set -uo pipefail

DIR=$(cd "$(dirname "$0")/.." && pwd)
PY="$DIR/scripts/tool.py"
TIMEOUT=${TIMEOUT:-5}

ENDPOINT=${BENCHMARKLLMS_ENDPOINT:-}
MODEL="" LADDER=49152 TASKS="general,coding"   # default ladder: 48k only; full ladder is opt-in
N=3 WARMUP=1 MAXTOKENS=256 TEMP=0 SEED=1234 OUT="" MODE=engine
H_NAME="" H_TOOLS="" H_ALIAS="" NO_BENCH=0
FLAGS="" FLAGS_F="" ENGINE_F="" EVERSION_F="" QUANT_F="" HF_F="" DRAFTER_F="" NOTES_F="" MAXCTX_F=""
ENGINE_DIR="" HARNESS_DIR="" HARNESS_ENDPOINT="" UUID_FULL=""
ENGINE_DIR_NAME="" ENGINE_DIR_VERSION="" ENGINE_DIR_COMMIT="" ENGINE_DIR_REMOTE=""
HARNESS_DIR_NAME="" HARNESS_DIR_VERSION="" HARNESS_DIR_COMMIT=""
REALNAME_F="" FT_F="" FT="" REAL="" CAND="" ASK=0 SAVE_PROFILE=0
SWAP_CONFIG=${BENCHMARKLLMS_SWAP_CONFIG:-} MODEL_DIR=${BENCHMARKLLMS_MODEL_DIR:-}
PROFILE=${BENCHMARKLLMS_PROFILE:-$HOME/.config/benchmarkllms/profile.json}
NO_SEARCH=${BENCHMARKLLMS_NO_SEARCH:-} HITS="" HF_URLS="" HF_DIR=""
CANDIDATES="8000 11434 8080 1234 4444"

while [ $# -gt 0 ]; do
  case $1 in
    --endpoint) shift; ENDPOINT=$1;; --model) shift; MODEL=$1;;
    --ladder) shift; LADDER=$1;; --tasks) shift; TASKS=$1;;
    --n) shift; N=$1;; --warmup) shift; WARMUP=$1;;
    --max-tokens) shift; MAXTOKENS=$1;; --temperature) shift; TEMP=$1;; --seed) shift; SEED=$1;;
    --out) shift; OUT=$1;; --mode) shift; MODE=$1;;
    --engine) shift; ENGINE_F=$1;; --engine-version) shift; EVERSION_F=$1;;
    --quant) shift; QUANT_F=$1;; --hf) shift; HF_F=$1;; --drafter) shift; DRAFTER_F=$1;;
    --flags) shift; FLAGS_F=$1;; --model-max-context) shift; MAXCTX_F=$1;; --notes) shift; NOTES_F=$1;;
    --engine-dir) shift; ENGINE_DIR=$1;; --harness-dir) shift; HARNESS_DIR=$1;;
    --harness-endpoint) shift; HARNESS_ENDPOINT=$1;; --uuid-full) UUID_FULL=1;;
    --harness-name) shift; H_NAME=$1;; --harness-tools) shift; H_TOOLS=$1;;
    --harness-model-alias) shift; H_ALIAS=$1;; --no-bench) NO_BENCH=1;;
    --ask) ASK=1;; --save-profile) SAVE_PROFILE=1;; --profile) shift; PROFILE=$1;;
    --real-name) shift; REALNAME_F=$1;; --fine-tuning) shift; FT_F=$1;;
    --swap-config) shift; SWAP_CONFIG=$1;; --model-dir) shift; MODEL_DIR=$1;;
    --no-search) NO_SEARCH=1;; --no-web) NO_SEARCH=1;;
    -h|--help) sed -n '7,14p' "$0"; exit 0;;
    *) if [ -d "$1" ]; then   # positional: engine dir, then harness dir — only a fork's own
                            # manifest and git can name a fork, so this is how you pass them
           if [ -z "$ENGINE_DIR" ]; then ENGINE_DIR=$1; else HARNESS_DIR=${HARNESS_DIR:-$1}; fi
         elif [ -z "$MODEL" ]; then MODEL=$1; else echo "unknown arg: $1" >&2; exit 2; fi;;
  esac
  shift
done

src() { if [ -n "$1" ]; then echo flag; elif [ -n "$2" ]; then echo dir; \
        elif [ "${3:-unknown}" != unknown ]; then echo probe; else echo unknown; fi; }
norm() { printf '%s' "${1:-}" | sed -E 's#^https?://##; s#/.*$##'; }   # defined where the profile key can use it
kv() { printf '%s\t%s\n' "$1" "${2:-unknown}"; }
pj() { python3 "$PY" json "${1:-}" 2>/dev/null || echo unknown; }   # reads JSON on stdin
cget() { curl -fsS --max-time "$TIMEOUT" "$@" 2>/dev/null; }

if [ -z "$ENDPOINT" ]; then
  for p in $CANDIDATES; do
    r=$(cget "http://127.0.0.1:$p/v1/models")
    if [ -n "$r" ]; then ENDPOINT="http://127.0.0.1:$p/v1"; break; fi
  done
fi
[ -n "$ENDPOINT" ] || { echo "no engine endpoint; pass --endpoint (see --help)" >&2; exit 1; }
[ "$UUID_FULL" = 1 ] && export BENCHMARKLLMS_UUID=full   # gpu uuid is truncated in posts
BASE=${ENDPOINT%/}; case $BASE in */v1) BASE=${BASE%/v1};; esac; BASE=${BASE%/}
CHAT="$BASE/v1/chat/completions"   # the OpenAI-compatible path is what makes this harness-independent

# ---- 1. engine: one endpoint, ~7 fields, identical on every platform ----------
SERVED=$(curl -fsS --max-time "$TIMEOUT" "$BASE/v1/models" 2>/dev/null)
ENGINE=unknown EVERSION=unknown FLAGS="" HF=unknown QUANT=unknown MAXCTX=unknown MD=$(cget "$BASE/props")
# flags the caller passes are the caller's answer; what we work out ourselves is below
if [ -n "$SERVED" ]; then
  MODEL=${MODEL:-$(printf '%s' "$SERVED" | pj "data.0.id")}
  EVERSION=$(cget "$BASE/version" | tr -d '\n')
  if [ "$ENGINE" = unknown ] && [ -n "$MD" ]; then ENGINE=llama.cpp; FLAGS=$(printf '%s' "$MD" | pj args | tr -d '\n'); fi
  if [ "$ENGINE" = unknown ]; then ENGINE=$(printf '%s' "$SERVED" | pj "data.0.meta.engine"); fi
fi
if [ "$ENGINE" = unknown ] && [ -n "$(cget "$BASE/info")" ]; then ENGINE=tgi; EVERSION=$(cget "$BASE/info" | pj version); fi
if [ "$ENGINE" = unknown ] && [ -n "$(cget "$BASE/api/version")" ]; then ENGINE=ollama; EVERSION=$(cget "$BASE/api/version" | pj version); fi
if [ "$ENGINE" = unknown ] && [ -n "$(cget "$BASE/info")" ]; then ENGINE=lmstudio; fi
[ "$ENGINE" = llama.cpp ] && { [ -n "$EVERSION" ] || EVERSION=$(cget "$BASE/version" | tr -d '\n'); }
if [ "$ENGINE" = unknown ]; then ENGINE=other; fi

# ---- 1b. name, quant, tuning: what the endpoint calls it is not always what it is ---
SEND=$MODEL   # what we put in the request body: the routable id, alias or not
OWNER=$(printf '%s' "$SERVED" | pj "data.0.owned_by")
[ "$ENGINE" = ollama ] && [ "$OWNER" = llama-swap ] && ENGINE=llama-swap
# a router answers /api/version as if it were ollama and serves whatever id it likes, so name the
# router, and let the questionnaire name what is actually behind it.
KEY="$(norm "$BASE") ${SEND:-unknown}"
PROF=$(python3 "$PY" profile get "$PROFILE" "$KEY" 2>/dev/null)   # answers from the last questionnaire here
pv() { printf '%s' "$PROF" | sed -n "s/^$1\t//p" | head -1; }
# a llama-swap selector's yaml or launcher names the file it boots, which is the only way an alias
# ever gets a real name without asking. One candidate is an answer; several is a question.
[ "$OWNER" = llama-swap ] && [ -r "${SWAP_CONFIG:-}" ] && CAND=$(python3 "$PY" swap "$SWAP_CONFIG" "$SEND")
REAL=${REALNAME_F:-}; RSRC=flag
if [ -z "$REAL" ]; then REAL=$(pv real_name); [ -n "$REAL" ] && RSRC=profile; fi
if [ -z "$REAL" ] && [ "$(printf '%s' "$CAND" | wc -w)" = 1 ]; then REAL=$CAND; RSRC=probe; fi
[ -z "$REAL" ] && { REAL=$MODEL; RSRC=alias; }   # the nickname is what is left, so the post says so
NI=$(python3 "$PY" nameinfo "$(basename "$REAL")")   # one call: quant and tuning both live in the filename
NIQ=$(printf '%s' "$NI" | sed -n 's/^quant\t//p'); NIT=$(printf '%s' "$NI" | sed -n 's/^tuning\t//p')

FILE=$(basename "${MODEL:-unknown}")
QUANT=${QUANT_F:-$(pv quant)}
[ -z "$QUANT" ] && [ "$RSRC" != alias ] && QUANT=$NIQ
[ -z "$QUANT" ] && QUANT=$(printf '%s' "$FILE" | sed -n 's/.*[-_]\(iq*[0-9][a-z0-9_]*\|nf[0-9]*\|q[0-9][a-z0-9_]*\)\.[gG][gG][uU][fF]$/\1/p')
if [ -n "$MD" ] && [ "$QUANT" = "" ]; then QUANT=$(printf '%s' "$MD" | pj "general.quantization_output_types"); fi
if [ "$QUANT" = "" ]; then QUANT=unknown; fi
FT=${FT_F:-$(pv fine_tuning)}   # a tuner is never guessed from a vibe: filename tokens, saved answer, flag, or the questionnaire
[ -z "$FT" ] && [ -n "$NIT" ] && FT=$NIT
[ -z "$FT" ] && FT=unknown
# HF: flag > saved questionnaire answer > the weights dir on this machine > what the engine itself
# reports > a web search. The last one knows it is a guess, and the post labels it `(likely)`.
HITS=$(python3 "$PY" hfsearch "$(basename "${REAL:-$MODEL}")")   # offline or no match: empty, and the field stays unknown
for d in "$HOME/.cache/huggingface/hub/models--$(printf '%s' "${MODEL:-}" | tr '/' '-' | tr 'A-Z' 'a-z')"; do
  [ -e "$d" ] && HF_DIR=$(basename "$d" | sed 's/models--//; s/-/\//; 1s/^/https:\/\/huggingface.co\//')
done
HF=${HF_F:-$(pv hf)}; HFSRC=flag
[ -z "$HF" ] && [ -n "$HF_DIR" ] && { HF=$HF_DIR; HFSRC=cache; }
[ -z "$HF" ] && [ -n "$MD" ] && HF=$(printf '%s' "$MD" | pj "general.basename")
[ -z "$HF" ] && HF=$(printf '%s' "$SERVED" | pj "data.0.meta.hf_repo")
[ -z "$HF" ] && { HF=$(printf '%s' "$HITS" | sed -n '1!d;s/\t.*//;p'); HFSRC=$(printf '%s' "$HITS" | sed -n '1!d;s/.*\t//;p'); }   # an exact match is used as-is; a likely one is a question, not a fact
[ -z "$HFSRC" ] && HF=unknown
if [ "$MAXCTX" = unknown ]; then
  MAXCTX=$(printf '%s' "$SERVED" | pj "data.0.meta.n_ctx")
  [ "$MAXCTX" = unknown ] && [ -n "$MD" ] && MAXCTX=$(printf '%s' "$MD" | pj "params.n_ctx")
  [ "$MAXCTX" = unknown ] && [ -n "$MD" ] && MAXCTX=$(printf '%s' "$MD" | pj "model_path.n_ctx")
  if [ "$MAXCTX" = unknown ]; then
    echo "note: $ENGINE did not report its max context; the pre-flight check cannot run" >&2
    echo "  (the harness config's contextWindow is a guess at this; pass --model-max-context)" >&2
  fi
fi

if [ -n "$ENGINE_DIR" ]; then
  idj=$(python3 "$PY" ident "$ENGINE_DIR")
  ENGINE_DIR_NAME=$(printf '%s' "$idj" | pj name); ENGINE_DIR_VERSION=$(printf '%s' "$idj" | pj version)
  ENGINE_DIR_COMMIT=$(printf '%s' "$idj" | pj commit); ENGINE_DIR_REMOTE=$(printf '%s' "$idj" | pj remote)
fi
if [ -n "$HARNESS_DIR" ]; then
  idj=$(python3 "$PY" ident "$HARNESS_DIR")
  HARNESS_DIR_NAME=$(printf '%s' "$idj" | pj name); HARNESS_DIR_VERSION=$(printf '%s' "$idj" | pj version)
  HARNESS_DIR_COMMIT=$(printf '%s' "$idj" | pj commit)
fi

SELFC=no
if [ -n "$HARNESS_ENDPOINT" ] && [ "$(norm "$HARNESS_ENDPOINT")" = "$(norm "$BASE")" ]; then
  SELFC=yes   # the harness driving this run is served by the engine it is measuring
  echo "self-contention: this session's own model is behind this endpoint, so its own inference" >&2
  echo "is in the queue for every request below. Run the script from a second terminal for a" >&2
  echo "publishable number." >&2
fi

# ---- 2. hardware: per-field, since no single tool covers what matters ---------
# GPU first, from a vendor CLI: fastfetch reports no VRAM for NVIDIA, and lists cards in DRM
# order, which is not NVML order.
GPUS=$(python3 "$PY" gpulist 2>/dev/null)
# fastfetch fills OS/CPU/RAM in ONE call, which matters for an agent (every call is a tool
# round-trip), and it runs on Linux, Windows and macOS. Never used for GPU (see above).
FF=$(fastfetch --format json 2>/dev/null)
ffb() { [ -n "$FF" ] && printf '%s' "$FF" | python3 "$PY" json "$1" 2>/dev/null; }
gb() { case "${1:-}" in ''|*[!0-9]*) printf '%s' "${1:-unknown}";; *) awk -v b="$1" 'BEGIN{printf "%.1f GB", b/1073741824}';; esac; }
OS=$(ffb OS.prettyName); CPU=$(ffb CPU.cpu); RAM=$(gb "$(ffb Memory.total)")
[ -z "$CPU" ] && CPU=unknown; [ -z "$RAM" ] && RAM=unknown; [ -z "$OS" ] && OS=unknown
case $(uname -s) in
  Linux)
    [ "$OS" = unknown ] && [ -r /etc/os-release ] && OS=$(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")
    [ "$CPU" = unknown ] && { CPU=$(lscpu -p=MODEL 2>/dev/null | grep -v '^#' | head -1); [ -z "$CPU" ] && CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//'); }
    [ "$RAM" = unknown ] && RAM=$(awk '/MemTotal/{printf "%.1f GB", $2/1048576}' /proc/meminfo 2>/dev/null)
    grep -qi microsoft /proc/version 2>/dev/null && OS="$OS (WSL2)"
    ;;
  Darwin)
    [ "$OS" = unknown ] && OS="macOS $(sw_vers -productVersion 2>/dev/null)"
    [ "$CPU" = unknown ] && CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
    [ "$RAM" = unknown ] && RAM=$(awk "BEGIN{printf \"%.1f GB\", $(sysctl -n hw.memsize 2>/dev/null || echo 0)/1073741824}")
    [ -z "$GPUS" ] && GPUS=$(python3 "$PY" mac 2>/dev/null)
    ;;
  MINGW*|MSYS*|CYGWIN*)
    psc() { powershell.exe -NoProfile -Command "$1" 2>/dev/null | tr -d '\r' | head -1; }
    [ "$OS" = unknown ] && OS=$(psc '(Get-CimInstance Win32_OperatingSystem).Caption')
    [ "$CPU" = unknown ] && CPU=$(psc '(Get-CimInstance Win32_Processor).Name')
    [ "$RAM" = unknown ] && RAM=$(psc '[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)')
    [ -z "$GPUS" ] && GPUS=$(python3 "$PY" wmi 2>/dev/null)
    ;;
esac
CPU=${CPU:-unknown}; RAM=${RAM:-unknown}; OS=${OS:-unknown}; GPUS=${GPUS:-[]}

MAXCTX=${MAXCTX_F:-$MAXCTX}   # the caller's flag wins, and the pre-flight check needs it
# flags > directories > saved questionnaire answers > endpoint guesses — decided once, here, so
# the questionnaire and the post can never disagree about which of them a value came from.
ENGINE_FINAL=${ENGINE_F:-${ENGINE_DIR_NAME:-$(pv engine)}}; [ -z "$ENGINE_FINAL" ] && ENGINE_FINAL=$ENGINE
ENGINE_V=${EVERSION_F:-${ENGINE_DIR_VERSION:-$(pv engine_version)}}; [ -z "$ENGINE_V" ] && ENGINE_V=$EVERSION
ENGINE_S=flag
if [ -z "$ENGINE_F" ]; then
  if [ -n "$ENGINE_DIR_NAME" ]; then ENGINE_S=dir
  elif [ -n "$(pv engine)" ]; then ENGINE_S=profile
  elif [ "$ENGINE" != unknown ]; then ENGINE_S=probe
  else ENGINE_S=unknown; fi
fi
# ---- 2b. questionnaire: what the probes cannot name, the human answers — once -----
if [ "$ASK" = 1 ]; then
  # multiple choice if the harness has it, this numbered list if it does not. A flag is the
  # caller's own answer; a saved answer or a probe is a guess, so it gets confirmed, not used.
  QENGINE="llama.cpp strata vllm sglang tgi ollama llama-swap lmstudio koboldcpp llamacpp-python other"
  QQUANT="q4_k_m q4_k_s q5_k_m q6_k q8_0 iq3_xxs iq4_xs Q4_0 fp8 compressed-tensors awq gptq bf16 other"
  QFT="none swift gsq-rco abliterated uncensored heretic other"
  MDLIST=""
  if [ -n "$MODEL_DIR" ] && [ -d "$MODEL_DIR" ]; then
    n=$(find "$MODEL_DIR" -maxdepth 2 -name '*.gguf' ! -name 'mmproj-*' 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] && [ "$n" -le 8 ] && MDLIST=$(find "$MODEL_DIR" -maxdepth 2 -name '*.gguf' ! -name 'mmproj-*' 2>/dev/null | sed 's#.*/##; s/\.gguf$//' | sort -u)
  fi
  q=0
  ask() { q=$((q + 1)); printf '  %s. %s\n' "$q" "$1"; shift; [ $# -gt 0 ] && printf '     -> %s\n' "$(printf '%s' "$*" | tr ' ' '\n' | awk 'NF{printf "%s%s", (n++ ? " | " : ""), $0} END{if (n) print ""}')"; }
  opts() { printf '%s' "$*" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ' | sed 's/ $//'; }   # a guess first, then the pinned list, no option twice
  src3() { if [ -n "$1" ]; then echo flag; elif [ -n "$(pv "$2")" ]; then echo saved; elif [ "$3" = dir ]; then echo dir; else echo 'nothing yet'; fi; }
  # a saved answer was given by a human, so it is not asked twice; only a guess from a filename, a
  # config or the endpoints gets confirmed
  fresh() { [ -n "$1" ] && return 1; [ -n "$(pv "$2")" ] && return 1; [ "$3" = saved ] && return 1; case "${3:-}" in dir) return 1;; esac; return 0; }
  echo "What I found about ${SEND:-this endpoint}:"
  printf '  model:  %s  [%s]\n'  "${REAL:-unknown}" "$(src3 "$REALNAME_F" real_name "$RSRC")"
  printf '  quant:  %s  [%s]\n'  "$QUANT" "$(src3 "$QUANT_F" quant '')"
  printf '  engine: %s  [%s]\n'  "$ENGINE_FINAL" "$(src3 "$ENGINE_F" engine "$( [ -n "$ENGINE_DIR_NAME" ] && echo dir)")"
  printf '  version: %s [%s]\n'  "$ENGINE_V" "$(src3 "$EVERSION_F" engine_version "$( [ -n "$ENGINE_DIR_VERSION" ] && echo dir)")"
  printf '  tuning: %s  [%s]\n'  "$FT" "$(src3 "$FT_F" fine_tuning '')"
  printf '  hf: %s  [%s]\n' "$HF" "$(src3 "$HF_F" hf "$( [ "$HFSRC" = search ] && echo search)")"
  printf '  harness: %s   tools: %s   alias: %s\n' "${H_NAME:-unknown}" "${H_TOOLS:-unknown}" "${H_ALIAS:-unknown}"
  printf '  profile: %s\n' "$([ -f "$PROFILE" ] && printf '%s [key: %s]' "$PROFILE" "$KEY" || echo 'none yet')"
  echo
  if [ -n "$REALNAME_F" ] || [ -n "$(pv real_name)" ]; then :   # flagged or already answered: not a question
  elif [ "$RSRC" = alias ]; then
    if [ -n "$CAND" ]; then ask "The endpoint serves \"$SEND\", which is a llama-swap alias. Which model is it really?" $(opts "$CAND" $MDLIST)
    elif [ -n "$MDLIST" ]; then ask "The endpoint serves \"$SEND\", which is a llama-swap alias. Which model is it really (full name as spelled — no nicknames)?" $MDLIST
    else ask "Which model is behind the \"$SEND\" alias (full name as spelled)?"; fi
  else ask "Is the model really $REAL (that is what the $([ "$RSRC" = probe ] && echo config || echo filename) says)?" "$MDLIST"; fi
  if [ -n "$QUANT_F" ] || [ -n "$(pv quant)" ]; then :
  elif [ "$QUANT" = unknown ]; then ask "What is the quantisation?" $QQUANT
  else ask "Is the quantisation $QUANT (that is what the filename says)?" "$(opts "$QUANT" $QQUANT)"; fi
  if [ -n "$ENGINE_F" ] || [ -n "$(pv engine)" ]; then :
  elif [ "$ENGINE_FINAL" = unknown ]; then ask "Which engine is serving this endpoint?" $QENGINE
  else ask "Is the engine really $ENGINE_FINAL (that is what the endpoints answer, and a fork can fake it)?" "$(opts "$ENGINE_FINAL" $QENGINE)"; fi
  if [ -n "$EVERSION_F" ] || [ -n "$(pv engine_version)" ]; then :
  elif [ "$ENGINE_V" = unknown ]; then ask "What is that engine's version?"
  else ask "Confirm the engine version $ENGINE_V (it is what the engine reported)"; fi
  if [ -n "$FT_F" ] || [ -n "$(pv fine_tuning)" ]; then :
  elif [ "$FT" = unknown ]; then ask "Any fine tuning (framework/method, if any)?" $QFT
  else ask "Is the fine tuning $FT (that is what the filename says)?" "$(opts "$FT" $QFT)"; fi
  if [ -n "$HF_F" ] || [ -n "$(pv hf)" ]; then :; elif [ -z "$HITS" ]; then :
  elif [ "$(printf '%s' "$HITS" | sed -n '1!d;s/.*\t//;p')" = exact ]; then :   # the org, the tuner words and the quant folder all line up: no question needed
  else ask "Which is the Hugging Face repo? (the search found these)" \
    "$(printf '%s' "$HITS" | awk -F'\t' '{printf "%s|%s\n", $1, ($2=="exact"?"certain":"likely")}')"; fi
  if [ -n "$H_NAME" ] || [ -n "$(pv harness_name)" ]; then :; else ask "Which harness is driving this run?"; fi
  if [ -n "$H_TOOLS" ] || [ -n "$(pv harness_tools)" ]; then :; else ask "Which tools does it expose?"; fi
  if [ "$q" = 0 ]; then echo "Nothing to ask — everything is known. Run it."; exit 0; fi
  echo
  echo "Then run it once with the answers, adding --save-profile so the next run remembers:"
  echo "  scripts/benchmarkllms.sh --real-name NAME --quant Q --engine E --engine-version V --fine-tuning T --save-profile"
  exit 0
fi

# ---- 3. ladder ---------------------------------------------------------------
E0=$(date -u +%s); T0=$(date -u '+%FT%T%z')   # the post reports when the run started and what it took
RUNS=$(mktemp)
if [ "$NO_BENCH" = 0 ]; then
  for t in $(printf '%s' "$TASKS" | tr ',' ' '); do
    seed="$DIR/assets/prompts/$t.seed.md"
    [ -r "$seed" ] || { echo "missing $seed" >&2; continue; }
    SHA=$(sha256sum "$seed" 2>/dev/null | cut -c1-12); [ -z "$SHA" ] && SHA=$(shasum -a 256 "$seed" 2>/dev/null | cut -c1-12)
    for tgt in $(printf '%s' "$LADDER" | tr ',' ' '); do
      if [ "$MAXCTX" != unknown ] && [ $((tgt + MAXTOKENS)) -gt "$MAXCTX" ] 2>/dev/null; then
        # stop, do not skip: a partial ladder is not the ladder, and a clamped point is a lie
        echo "stop: ${tgt} tokens + ${MAXTOKENS} output does not fit $REAL's max context (${MAXCTX} tokens)." >&2
        echo "  raise max_context_window to at least $(( (tgt + MAXTOKENS + 1023) / 1024 ))k, or benchmark a lower ladder." >&2
        echo "  (pass --model-max-context if the engine does not report it)" >&2
        exit 1
      fi
      i=0
      while [ "$i" -lt $((N + WARMUP)) ]; do
        i=$((i+1))
        body=$(python3 "$PY" body "$seed" "$DIR/assets/prompts/filler.txt" "$tgt" "$SEND" "$MAXTOKENS" "$TEMP" "$SEED" "$ENGINE" "$t" "$SHA" "$i") || continue
        r=$(mktemp)
        bf=$(mktemp)   # a 48k body is ~200 KB in one arg and a single arg caps at 128 KB
        printf '%s' "$body" > "$bf"
        t1=$(curl -sS --max-time 600 -N -X POST -H 'content-type: application/json' --data-binary "@$bf" \
             -o "$r" -w '%{http_code} %{time_starttransfer} %{time_total}' "$CHAT" 2>/dev/null)
        if [ -z "$t1" ]; then   # a dropped request must show up in the post, not vanish
          [ "$i" -le "$WARMUP" ] && { rm -f "$r" "$bf"; continue; }
          printf '%s\t%s\t%s\t%s\t%s\t\t\t\t\t%s\tcurl-fail\t\t\t\t\n' \
            "$t" "$tgt" "$SHA" "$MODEL" "$ENGINE" "$i" >> "$RUNS"; rm -f "$r" "$bf"; continue
        fi
        code=${t1%% *}; rest=${t1#* }; ttft=${rest%% *}; total=${rest#* }
        [ "$code" = 200 ] || echo "  $CHAT -> $code" >&2
        usage=$(grep -oE '"usage": *\{[^}]*}' "$r" | tail -1)
        pt=$(printf '%s' "$usage" | sed -n 's/.*"prompt_tokens": *\([0-9]*\).*/\1/p')
        ct=$(printf '%s' "$usage" | sed -n 's/.*"completion_tokens": *\([0-9]*\).*/\1/p')
        # fallback: llama.cpp reports prompt_n/predicted_n in its own timings block, and the
        # draft counters come from the same place, which is how DRAFTER gets an acceptance rate
        [ -z "$pt" ] && pt=$(grep -oE '"prompt_n": *[0-9]*' "$r" | tail -1 | tr -dc '0-9')
        [ -z "$ct" ] && ct=$(grep -oE '"predicted_n": *[0-9]*' "$r" | tail -1 | tr -dc '0-9')
        draft=$(grep -oE '"draft_n": *[0-9]*' "$r" | tail -1 | tr -dc '0-9')
        accepted=$(grep -oE '"draft_n_accepted": *[0-9]*' "$r" | tail -1 | tr -dc '0-9')
        eps_ms=$(grep -oE '"prompt_ms": *[0-9][0-9.]*' "$r" | tail -1 | sed 's/[^0-9.]//g')
        eps_pred_ms=$(grep -oE '"predicted_ms": *[0-9][0-9.]*' "$r" | tail -1 | sed 's/[^0-9.]//g')
        [ "$i" -le "$WARMUP" ] || printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$t" "$tgt" "$SHA" "$MODEL" "$ENGINE" "${pt:-unknown}" "${ct:-unknown}" "$ttft" "$total" "$i" "$code" "${draft:-}" "${accepted:-}" "${eps_ms:-}" "${eps_pred_ms:-}" >> "$RUNS"
        rm -f "$r" "$bf"
      done
    done
  done
fi

# ---- 4. emit: one emitter, so the post and the yaml can never disagree -------
META=$(mktemp)
{ kv schema benchmarkllms/v2; kv date "$(date -u +%F)"
  kv model "$REAL"; kv model_source "$RSRC"; kv quant "$QUANT"; kv fine_tuning "$FT"
  kv hf "${HF_F:-$HF}"; kv hf_source "$( [ -n "$HF_F" ] && echo flag || echo "${HFSRC:-$(pv hf | grep -q . && echo profile || echo unknown)}")"
  kv drafter "${DRAFTER_F:-unknown}"; kv flags "${FLAGS_F:-$FLAGS}"
  printf 'notes	%s
' "$NOTES_F"   # the human's own field: blank until they write it, never kv's 'unknown'
  kv engine_source "$ENGINE_S"
  kv engine "$ENGINE_FINAL"; kv engine_version "$ENGINE_V"
  kv engine_commit "${ENGINE_DIR_COMMIT:-unknown}"; kv engine_remote "${ENGINE_DIR_REMOTE:-unknown}"
  if [ "${HARNESS_DIR_NAME:-unknown}" != unknown ] && [ -n "$HARNESS_DIR_NAME" ]; then kv harness_source dir
  elif [ -n "$H_NAME" ]; then kv harness_source config   # the agent read its own config, which is real
  else kv harness_source unknown
  fi
  kv harness_name "${H_NAME:-${HARNESS_DIR_NAME:-unknown}}"; kv harness_tools "$H_TOOLS"
  kv harness_version "${HARNESS_DIR_VERSION:-unknown}"; kv harness_commit "${HARNESS_DIR_COMMIT:-unknown}"
  kv harness_model_alias "$H_ALIAS"; kv self_contention "$SELFC"
  kv mode "$MODE"; kv endpoint "$BASE"; kv os "$OS"; kv cpu "$CPU"; kv ram "$RAM"
  kv kernel "$(uname -sr 2>/dev/null)"
  kv source client; kv batch 1; kv prefix_cache off; kv temperature "$TEMP"; kv seed "$SEED"
  kv n "$N"; kv statistic median; kv warmup "$WARMUP"; kv max_tokens "$MAXTOKENS"
  kv model_max_context "${MAXCTX_F:-${MAXCTX:-unknown}}"; kv ladder "$LADDER"
  kv bench_start "$T0"; kv bench_end "$(date -u +%FT%TZ)"; kv total_time_s "$(( $(date -u +%s) - E0 ))s"
  printf 'gpus\t%s\n' "$GPUS"
} > "$META"
POST=$(python3 "$PY" post "$META" "$RUNS")
if [ "$SAVE_PROFILE" = 1 ]; then   # the next run on this endpoint starts from these answers
  python3 "$PY" profile set "$PROFILE" "$KEY" "real_name=$REALNAME_F" "quant=$QUANT_F" \
    "engine=$ENGINE_F" "engine_version=$EVERSION_F" "fine_tuning=$FT_F" "hf=$HF_F" \
    "harness_name=$H_NAME" "harness_tools=$H_TOOLS" >&2
fi
if [ -n "$OUT" ]; then mkdir -p "$(dirname "$OUT")"; printf '%s\n' "$POST" > "$OUT"; printf 'wrote %s\n' "$OUT" >&2; fi
python3 "$PY" post "$META" "$RUNS" reply   # the reply the user reads: numbers, then the fenced post
