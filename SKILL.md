---
name: benchmark-llms
description: Benchmarks a local LLM (prefill and decode throughput, TTFT, context ladder) and generates a r/BenchmarkLLMs post. Use when benchmarking a model, measuring tok/s, prefill speed, TTFT or time to first token, comparing quantisations or draft models, or when asked to generate or fill a BenchmarkLLMs post.
license: MIT
compatibility: Designed for any Agent Skills harness with a shell tool. Requires bash, curl, python3. Reads hardware via nvidia-smi/rocm-smi/vulkaninfo/fastfetch; needs an OpenAI-compatible engine endpoint.
allowed-tools: Bash Read Write
metadata:
  author: altmush
  version: "1.0"
---

# BenchmarkLLMs

Run one command, paste its output. The script does the measuring; you only fill the
`Harness:` block, because nothing else can know it.

```sh
scripts/benchmarkllms.sh --out BenchmarkLLMs-results/<model>_<quant>_<YYYY-MM-DD>.md
```

## Steps

1. **Confirm the endpoint.** Pass `--endpoint http://host:port/v1`. Default from
   `$BENCHMARKLLMS_ENDPOINT`, else it probes localhost. If your harness's config knows the
   endpoint (pi: `~/.pi/agent/models.json`), pass it — the harness knows the *endpoint*,
   the engine knows the *model*.
2. **Pass what only you know:** your own directory as the second positional argument (or
   `--harness-dir`) plus `--harness-name`, `--harness-tools`, `--harness-model-alias` and
   `--harness-endpoint`. Fill these from your own config, verbatim. Never guess them, never
   infer the model's real name from a routing alias.

   If the script warns about **self-contention** — your own model is behind the endpoint being
   measured — your inference is in the queue for every request it makes. Say so, and suggest the
   user run the script from a second terminal (or from a session on a different model) before
   they post the numbers.

3. **Answer the questionnaire before the ladder.** Run `scripts/benchmarkllms.sh --ask` with the
   same endpoint and harness flags. It probes what it can and prints one question per field it
   could not name (model name behind a router alias, quant, engine, engine version, fine tuning).
   Ask those questions **as multiple choice** if your harness can, otherwise paste the numbered
   list as-is. Then run once with the answers as flags and add `--save-profile`, so the next run on
   this endpoint starts from them. Do not answer for the user from memory or vibes, and do not post
   a router nickname as the model name — the full name on the weight file is what carries the quant
   and the tuner.

4. Run the script **once, in the foreground, and wait for it.** Do not background it, do
   not poll it, do not start it again while it is running — one call is the whole benchmark and
   a default run is 8 requests. It is slow on purpose: a cold 48k point can take minutes on its
   own, so if it looks slow that is the measurement, not a hang.

   Defaults are the subreddit defaults (ladder `49152` (48k) only, tasks
   `general,coding`, n=3 median, warmup 1, temp 0, seed 1234, max_tokens 256). Do not change
   them unless asked — the whole value of the site is that everyone runs the same point. Ask
   before adding ladder points; the full ladder `0,16384,32768,49152,65536` is opt-in.

   The first positional argument is the engine's directory when it is a fork — only the
   manifest and git in that directory can name a fork, and that beats what the script can guess
   from endpoints. Flags beat directories; directories beat guesses.

   If the script stops before making a request, the point does not fit the model's context.
   Tell the user to raise `max_context_window` or benchmark a lower ladder, and do not silently
   run a lower point for them — that is their decision, and the post says which point it is.
5. Fill **`Additional Notes (human):`** — it is the human's field and the only prose in the
   post. Put anything that would change a reader's conclusion there (offloading, throttling, a
   point that did not fit, a warm cache, an engine name you had to pass by hand, a questionnaire
   answer you were given).
6. **The script's last screen is the reply. Pass it on** — greeting, the results to read, the same
   post fenced for pasting into the subreddit, the timings, and any question nobody answered. Do not
   reshuffle it into your own format; the fenced `yaml` block at the bottom is part of the post (it is
   what makes posts searchable) and must stay machine-readable.
7. Answer the follow-up questions it lists before handing the post over as final; if there are none,
   say so in one line.

## Rules

- **The prompts in `assets/prompts/` are fixed text.** Changing one changes the meaning of
  every number in the post, so it is hashed in the output. Do not paraphrase them.
- Report `unknown` for anything you cannot read. Never guess, never fail the run.
- Any field whose units are in the schema (`tok/s`, `GB`, `s`) keeps those units.
- The ladder must stay cold: the script disables prefix cache per request. If your engine
  ignores that, say so in `Additional Notes (human):`.
- `references/schema.md` is the field reference and enum list. Read it before changing a
  field name, a unit, or an enum value — the schema is shared with the subreddit.
- `Fine Tuning:` is a row of the post. It is filled from the name on the weight file, from a saved
  questionnaire answer, or from the user — never from a guess about what a suffix "looks like".
