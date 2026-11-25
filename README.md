# BenchmarkLLMs

![BenchmarkLLMs](<assets/GITHUB BANNER.png>)

Benchmark a local LLM and get a ready-to-post write-up for [r/BenchmarkLLMs](https://reddit.com/r/BenchmarkLLMs/).
Every run measures the same way — same prompts, same units, same ladder point, same settings — so posts
are comparable with each other. It's an [Agent Skill](https://agentskills.io/specification): a `SKILL.md`,
a script, fixed prompts, and a schema. Ask an agent to do it, don't run the script yourself.

Works in any harness with a shell tool: pi, Claude Code, OpenCode, Codex CLI, Gemini CLI, Cursor, Amp.

## How to run it

In Pi:

```
/skill:benchmark-llms
```

In any other harness, say **"benchmark this model"**. That's the whole interface: the agent runs the
script for you, asks you any open questions first, and saves a copy of the post in
`BenchmarkLLMs-results/<model>_<quant>_<YYYY-MM-DD>.md`.

The script's last screen is the reply: readable results, the post fenced for copy-pasting, the timings,
and any question nobody answered. Paste it into the subreddit.

**What the default run measures.** One ladder point: 48k context, both tasks. Fixed prompts (hashed),
median of 3 runs, warmup 1, batch 1, prefix cache off, temperature 0, seed 1234, max tokens 256. The
full ladder (`0,16384,32768,49152,65536`) is opt-in with `--ladder`.

**What you get.** The post, plus a copy in `BenchmarkLLMs-results/` — that folder is gitignored and holds
*your* posts, so a model on your machine becomes a curve instead of a one-off post.

**It asks, once.** Whatever it cannot name — the real model behind a router alias, the quant, the engine,
its version, fine tuning — it asks you, and remembers your answers per endpoint+alias
(`~/.config/benchmarkllms/profile.json`). The next run there does not ask again. A field it found by
searching the web is labelled `(likely)` in the post; only what it can prove goes unlabelled.

**Additional flags** the agent can pass when it knows better than to ask:
`--endpoint`, `--model`, `--ladder`, `--quant`, `--engine`, `--engine-version`, `--hf`,
`--fine-tuning`, `--real-name`, `--flags`, `--drafter`, `--model-max-context`, `--notes`, `--uuid-full`.
Flags beat directories, directories beat guesses. If the session's own model sits behind the endpoint
being measured, say so — that run is a smoke test, not a post.

## How to see prior runs

In Pi:

```
/skill:benchmark-llms-history
```

Elsewhere, say **"show me the past BenchmarkLLMs runs"**. The
[`benchmark-llms-history`](benchmark-llms-history/) skill reads the yaml block of every post in
`BenchmarkLLMs-results/` and prints them as one table — model, quant, engine, cold and warm tok/s and
TTFT, date — sorted fastest first. Same skill format as the benchmark itself, so install it the same way.

## Install

Symlink or copy this directory — **named `benchmark-llms/`**, some harnesses enforce that — into:

| Harness | Put it in |
|---|---|
| pi | `~/.agents/skills/` (or `./.agents/skills/` for one project) |
| Claude Code | `~/.claude/skills/` |
| OpenCode / Codex CLI / Gemini CLI / Cursor | their skills dir, or `./.agents/skills/` |
| anything else | `AGENTS.md` says where to look |

## The rules that make posts comparable

Pinned in [`references/schema.md`](references/schema.md) and on the subreddit: the fixed prompts, the
default ladder, `batch: 1`, `prefix_cache: off`, `temperature: 0`, `seed: 1234`, `n: 3` median, the
field names and their units, the enums. Check the model's max context before the ladder and skip a
point that does not fit — never clamp it. In the posted block, GPU uuids are truncated to 8 characters
and the endpoint keeps the port but drops the host; the `notes` field is yours, so don't put a model
path in it.
