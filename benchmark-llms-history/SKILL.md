---
name: benchmark-llms-history
description: Renders the table of past BenchmarkLLMs posts from BenchmarkLLMs-results/ — one table for reading, the same table fenced for copy-paste, sorted by tok/s highest first. Use when listing past results, showing the results history, comparing previous runs, building a results curve, or when asked for a leaderboard of BenchmarkLLMs posts.
license: MIT
compatibility: Any Agent Skills harness with a shell tool. Requires bash and python3 (stdlib only). Reads the fenced yaml block of the posts in BenchmarkLLMs-results/.
allowed-tools: Bash Read Write
metadata:
  author: altmush
  version: "1.0"
---

# BenchmarkLLMs history

One command, paste its output.

```sh
scripts/history.py            # reads ./BenchmarkLLMs-results/
scripts/history.py path/to/dir
```

It prints, per task: the table **rendered** for a human, then the same table inside a fenced
block for copy-paste. Columns are fixed:

`LLM | quant | engine | engine version | tok/s cold | ttft cold | tok/s warm | ttft warm | date`

## Steps

1. Run the script, paste what it printed — both the readable table and the fenced one, that is the
   point of the second copy.
2. One row per post **per task**, so a post that ran `general,coding` appears twice. If the user
   wants one row per post, they have to pick a task; do not average the two for them.
3. Sorted by **tok/s cold, highest first**. `cold` is the fixed default ladder point (48k), or the
   highest point the post reached when it never got there. `warm` is that point measured with the
   prefix cache ON — which the rules forbid, so most posts have nothing in the warm columns, and a
   post that ignored the rule has nothing in the cold ones. Say so when it happens.
4. `-` means the post has no such number. Never a zero, and never a number you worked out yourself:
   the script reads only the fenced `yaml` block of each post, because that is the part of a post
   that is machine-readable.
5. A post with no yaml block is skipped, not an error. If the user expected one in the list, that is
   why it is missing.
