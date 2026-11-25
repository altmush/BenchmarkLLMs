# AGENTS.md

For harnesses that read AGENTS.md but not Agent Skills.

Generating a r/BenchmarkLLMs post: run `scripts/benchmarkllms.sh --ask` first and ask the user the
questions it prints (multiple choice if you can, its numbered list if you cannot); then run
`scripts/benchmarkllms.sh --out BenchmarkLLMs-results/<model>_<quant>_<YYYY-MM-DD>.md --save-profile` with the
answers as flags, and paste its output. Fill `Harness:` and `Additional Notes (human):` yourself —
no command can know them — and keep the fenced `yaml` block machine-readable. `references/schema.md`
is the field reference; `assets/post.md` is the template. Do not change the fixed prompts in
`assets/prompts/`. The script's final screen is the reply — greeting, readable results, the post
fenced for pasting, the timings, the open questions — pass it on as it is. Answer the post twice in your reply: once readable, once fenced for copy-paste.
