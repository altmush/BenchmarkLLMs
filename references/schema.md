# Schema — benchmarkllms/v2

The subreddit and the skill read this file. Changing a field name, a unit, or an enum value
here changes every post, so bump `schema:` when you do — this is v2.

v2 added `fine_tuning`, `model_source`, the questionnaire and its saved answers, and `strata` and
`iq3_xxs` to the enums. A v1 post is still comparable, it just cannot name a tuner.

## The two things being measured

The ladder measures the **engine** (mode `engine`). A harness running the fixed task through
itself measures the **harness** (mode `harness`): system prompt tokens, tool round trips and
thinking tokens are part of that number and are not part of the engine's. Every post says
which one produced its numbers. Never compare a `harness` post to an `engine` post.

## Rules that make numbers comparable

These are the reasons posts on other subreddits are not comparable. They are the strict part
of this subreddit, and they are not arbitrary:

- **Fixed prompts.** `assets/prompts/general.seed.md` (general writing) and
  `coding.seed.md` (coding). The prompt text is fixed and hashed (`seed_sha256`), so a ladder
  point means the same task in every post. Paraphrasing the prompt invalidates the hash.
- **Fixed context ladder.** Default is `49152` (48k) — one point, both tasks. The full ladder
  `0,16384,32768,49152,65536` is opt-in with `--ladder`, and `0` is the cold baseline (the only
  point comparable to numbers people already post elsewhere, so it is worth adding on purpose).
  Check `model_max_context` **before** the first request, counting the output budget: a point
  that does not fit **stops the run** with "raise max_context_window, or benchmark a lower
  ladder". Do not clamp it, because a clamped 48k point reads like a win and is a lie.
- **`prefix_cache: off`, `batch: 1`.** A warm prefix cache makes a run 3–10× faster, so a
  ladder is meaningless if run 1 warms run 2. Non-negotiable.
- **A `# TLDR` block at the top** of every output: one line per task, decode tok/s at each
  ladder point actually measured. The machine block below is the authoritative copy; the TLDR is
  the part a human reads.
- **`temperature: 0`, `seed: 1234`, `n: 3`, `statistic: median`, `warmup: 1`,
  `max_tokens: 256`.** A fixed output budget, because output length *is* the denominator of
  decode throughput. Report the actual `out_tokens` too — that is how you spot a model that
  quit early.
- **`source: client`** (measured around the HTTP request: time to first byte, then first→last
  token) or **`source: server`** (engine counters). Say which. Wall-clock and engine-side
  numbers are not the same measurement.
- **Fixed enums**, exact spelling, so Reddit's substring search can find you: `vllm`,
  `llama.cpp`, `strata`, `sglang`, `tgi`, `ollama`, `llama-swap`, `lmstudio`, `koboldcpp`, `llamacpp-python`,
  `other`. Engine detection is best-effort (a router answers some of the same endpoints as the
  engine behind it), so the script's `--engine`, `--engine-version`, `--quant`, `--hf`,
  `--flags`, `--drafter` and `--model-max-context` flags always win over what it guessed.
  Quantisation: `q4_k_m`, `q4_k_s`, `q5_k_m`, `q6_k`, `q8_0`, `iq3_xxs`, `iq4_xs`, `Q4_0`, `fp8`,
  `compressed-tensors`, `awq`, `gptq`, `bf16`, `other`. `q4_k_m` and `Q4_0` and `fp8` are three
  different models wearing the same label, and version goes in its own field, never in the enum.
  Fine tuning: `none`, `swift`, `gsq-rco`, `abliterated`, `uncensored`, `heretic`, `other` — what
  a tuner is called is a name, not a number, so it is spelled as the author spells it.
- **Units are in the name**: `tok/s`, `ttft_s`, `vram_gb`, `ram_gb`. A number without its unit
  is not a field.

## Fields

`schema`, `date` (also in the filename, on purpose — Reddit search cannot see filenames),
`model` (canonical name **from the engine**, not from a routing alias), `model_source`, `quant`,
`fine_tuning`, `hf`.

`model_source` is `flag` > `profile` > `dir` > `probe` > `alias`: an alias is a nickname a router
invented (`my-router-alias`), and a nickname is not a model name — say what the full name on the
weight file is (`Swift-Qwen3.8-Flash-Next-IQ3_XXS-abliterated-SC117`), because quant and tuner
live in it and the post searches on them. `fine_tuning` is read from the same name when the name
is real, and otherwise it is the human's answer to the questionnaire.

**The questionnaire.** `--ask` runs the probes and prints what it found plus one question per field
it could not name, with its guess as the first option. The harness asks that as multiple choice if
it has it, and as a numbered list if it does not. Answers are saved per endpoint+alias
(`--save-profile`, `~/.config/benchmarkllms/profile.json`, `--profile FILE` to move it), so the
next run on the same endpoint starts from them — as a guess to confirm, never as a fact.

`engine: {name, version, flags, drafter}` — the engine reports these about itself, which is
why they are reliable across every platform. `flags` is the engine's own launch args.

`harness: {name, tools, model_alias, endpoint}` — the only block the agent fills, because no
command can know it. `model_alias` is the harness's own name for its model, kept verbatim: it
is not the model's real name (a router can point one alias at different models on different
days), so `model` must come from the engine.

`identity`: **flags > directories > guesses**. Positional args (or `--engine-dir`,
  `--harness-dir`) point at directories, and the name/version/commit/remote come from the
  manifest and git inside them — that is the only way a fork of a fork can ever be named
  correctly. `measurement.self_contention: true` means the harness driving the run is served by
  the engine being measured, so its own inference is in the queue: fine for a smoke test, not
  for a post.

`os`, `cpu`, `ram_gb`, `gpus[]`, `measurement{}` (see the rules above), `model_max_context`,
`runs[].task`, `seed_sha256`, `quality{}`, `notes`.

`gpus[].id` = **NVML index** (or the vendor CLI's own index), and record `uuid` — **truncated
  to 8 characters in the posted block**, since it is a per-device serial and a screenshot you
  post elsewhere gives the whole thing away (`--uuid-full` keeps it in the local record). An
  endpoint host is home-network layout, so the posted block keeps the port and drops the host.
  Your `notes` free text is yours: do not put a model path in it. Two posts
about one machine otherwise disagree about which card is `#0`, because DRM card order is not
NVML order. Per-GPU `vram_gb` is the most-searched field on the subreddit and the one tool
that covers everything else does not report it for NVIDIA — so use the vendor CLI, not
`fastfetch`, for GPU rows.

`identity_source` on both: engine is `flag` > `dir` > `probe` > `unknown`; harness is `dir` >
`config` > `unknown` (the agent reading its own config is a real source, so it is not marked).
A **probe is a guess** — a fork answers the same endpoints as its upstream — so a guessed engine
name gets a "verify" marker in the human block instead of being presented as fact.
`Additional Notes (human):` is the human's field, and the only prose in the post.

`runs[].points[]`: `target_ctx`, `actual_ctx` (read back from `usage.prompt_tokens`; padding
is approximate, so actual is the honest number), `prefill_tps`, `decode_tps`, `ttft_s`,
`out_tokens`, and the stdevs. A ladder with one run per point is a single run of a noisy
desktop, so `runs:` must be ≥3 and the reported number is the median.

## Platform notes

- **Windows:** `nvidia-smi` exists, so NVIDIA needs no special path. PowerShell CIM for
  CPU/RAM/OS. `Win32_VideoController.AdapterRAM` is a DWORD and caps at 4 GB — it lies about
  every bigger card, so prefer the vendor CLI and write `unknown` rather than the WMI number.
- **WSL2:** RAM via `/proc/meminfo` is the VM's, not the host's. Detect via `microsoft` in
  `/proc/version` and write `os: "<distro> (WSL2)"` so readers can discount it.
- **Apple Silicon:** memory is unified — RAM and VRAM are the same pool. Report total once and
  say so in `notes`. No `nvidia-smi`, no `rocm-smi`: `system_profiler`.
- **Never `sudo`.** A probe that needs root prompts, and a prompt inside a skill is a stalled
  session. If it needs root, it is not a field.
