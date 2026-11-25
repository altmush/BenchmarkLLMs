# BenchmarkLLMs

The same fields, the same units, the same prompts, the same ladder — for local LLM
benchmarks. Post the output to [r/BenchmarkLLMs](https://reddit.com/r/BenchmarkLLMs).

An [Agent Skill](https://agentskills.io/specification): one `SKILL.md`, a collector script,
fixed prompts, and a schema. Any harness with a shell tool can run it — pi, Claude Code,
OpenCode, Codex CLI, Gemini CLI, Cursor, Amp — and `AGENTS.md` points the ones that only read
`AGENTS.md` here.

## Run it

```sh
scripts/benchmarkllms.sh --endpoint http://localhost:8000/v1 \
  --harness-name pi --harness-tools "read bash edit write"
```

It prints the post; paste it. `--out BenchmarkLLMs-results/<model>_<quant>_<YYYY-MM-DD>.md` keeps a
copy, so a model on your machine becomes a curve instead of a one-off post. Out of the box the run
benchmarks **one point: 48k context** (both tasks) — the full ladder is opt-in. Say the line the
script prints above the post: it is ready to paste into
[r/BenchmarkLLMs](https://reddit.com/r/BenchmarkLLMs/).

## Answer the questionnaire once, not every time

`--ask` runs the probes and prints a question for everything it cannot name: the real model behind
a router alias, quant, engine, engine version, fine tuning. Multiple choice if your harness has it,
a numbered list if it does not. `--save-profile` keeps the answers per endpoint+alias
(`~/.config/benchmarkllms/profile.json`), so the next run there starts from them — as a guess to
confirm, never as a fact. `--real-name`, `--quant`, `--engine`, `--engine-version`,
`--fine-tuning`, `--swap-config`, `--model-dir` and `--profile` are the flags the answers turn into
(`$BENCHMARKLLMS_SWAP_CONFIG`, `$BENCHMARKLLMS_MODEL_DIR`, `$BENCHMARKLLMS_PROFILE` when a harness
cannot pass flags — the swap config is how a router alias gets resolved on its own, the model dir is
where it looks for candidates when it cannot).

Install for everyone (symlink or copy this directory **named `benchmark-llms/`** — some
implementations enforce that the directory matches `name:` in the frontmatter):

| Harness | Put it in |
|---|---|
| pi | `~/.agents/skills/` (or `./.agents/skills/` for one project) |
| Claude Code | `~/.claude/skills/` |
| OpenCode / Codex CLI / Gemini CLI / Cursor | their skills dir, or `./.agents/skills/` |
| anything else | `AGENTS.md` says where to look |

Slash-command invocation (`/benchmark-llms`) works in pi; elsewhere the trigger is the skill
`description`, so say "benchmark this model" instead of relying on the command existing.

## What the script fills, and who fills the rest

One call each, ordered by fields-per-call, because for an agent every call is a tool
round-trip:

1. **Engine over HTTP** → model, quant, engine, version, flags (engines report their own
   launch args), draft counters. Same code path on Linux, Windows, macOS, WSL, containers.
2. **Vendor GPU CLI** (`nvidia-smi` — on Windows too — then `rocm-smi`, then
   `vulkaninfo --summary`) → GPU name, **VRAM**, driver, NVML index, UUID.
3. **`fastfetch --format json`** → OS, CPU, RAM, in one call. Not used for GPU: on Linux it
   reports no VRAM for NVIDIA, and it lists cards in DRM order, which is not NVML order.
4. **Platform fallbacks** if fastfetch is absent (`/proc`, `lscpu`, `system_profiler`,
   PowerShell CIM).

The agent fills the `Harness:` block from its own config — no command can know it — and
`Additional Notes (human):` from what it noticed. Everything else is the script's.

## Also in this repo: `benchmark-llms-history/`

Its own skill, for the curve rather than the post: `scripts/history.py` reads the fenced `yaml` block
of every post in `BenchmarkLLMs-results/` and prints the table — LLM, quant, engine, engine version,
cold and warm tok/s, cold and warm TTFT, date — once rendered for reading and once fenced for
copy-paste, sorted by tok/s highest first. Install it the same way, named `benchmark-llms-history/`.

The last screen of a run **is the reply**: the greeting, the results to read, the same post fenced
for copy-pasting into the subreddit, the start/end/total time, and any question nobody answered. The
header numbers are the fixed ladder point (medians across tasks); `Warm` is that point, `cold` is the
`0` baseline. Pass it on as it is.

## The part that makes posts comparable

In `references/schema.md` and pinned on the subreddit. Fixed prompts (hashed), default ladder
48k (`0,16384,32768,49152,65536` opt-in), `batch: 1`, `prefix_cache: off`, `temperature: 0`, `seed: 1234`,
`n: 3` median, warmup 1, `max_tokens: 256`, units in the field names, enums pinned. Check
`model_max_context` before the ladder and **skip** a point that does not fit — never clamp it.

## Run it from somewhere that is not the model you are measuring

```sh
scripts/benchmarkllms.sh /path/to/engine-dir /path/to/your-harness --out BenchmarkLLMs-results/<model>_<quant>_<YYYY-MM-DD>.md
```

Positional args are directories, and they beat endpoint guessing: only the manifest and git
*inside* a fork's directory can name a fork (flags beat directories, directories beat guesses).
If your own session is served by the engine under test, the script says so
(`measurement.self_contention: true`) — that run is a smoke test, not a post, because your
inference is in the queue for every request. Run it from a second terminal for a publishable
number, and keep the polling at one blocking call: nothing polls, the shell tool waits for the
script to finish.

**Privacy, in the posted block:** GPU uuid truncated to 8 chars (`--uuid-full` for your local
record), endpoint keeps the port and drops the host, `notes` is yours — do not put a model path
in it.

## What it cannot know

- Engine detection is best-effort; override with `--engine`, `--engine-version`, `--quant`,
  `--hf`, `--flags`, `--drafter`, `--model-max-context`, `--notes`, `--real-name`,
  `--fine-tuning`. Flags always win. What a flag cannot know, the questionnaire asks — and remembers.
- A router in front of the engine (llama-swap, LiteLLM, OpenRouter) can point one stable
  alias at a different model on a different day, and may not forward the cache-busting field —
  so ladder points can be warm. Say so in `Additional Notes (human):`.
- No tokenizer dependency, so ladder padding is approximate and `actual_ctx` is the engine's
  own count, not the target.
- `decode_tps` needs an engine that reports draft counters or usage tokens; otherwise the
  client-side measurement around the request is used and `source:` says which.
