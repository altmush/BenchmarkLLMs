#!/usr/bin/env python3
"""benchmark-llms-history: every post in BenchmarkLLMs-results/ as a table — rendered for a human,
then the same table fenced for copy-paste.

cold = the `0` baseline point (nothing cached, tiny prompt). warm = the fixed default ladder point
(48k = 49152), or the highest point the post reached when it never got there. One row per post x
task; sorted by tok/s, highest first (whichever column that post actually has). '-' = no such number
in that post — never a zero, and never a number I worked out on the spot.

Reads the fenced yaml block, because that is the part of a post that is machine-readable. Stdlib
only; a .md with no yaml block is skipped, not an error.
"""
import glob, json, os, re, sys

COLS = ["LLM", "quant", "engine", "engine version", "tok/s cold", "ttft cold",
        "tok/s warm", "ttft warm", "date"]
POINT = re.compile(r"^\s+- (\{.*\})$")


def rows_for(path):
    txt = open(path, errors="replace").read()
    block = txt.split("```yaml")
    if len(block) < 2:
        return []
    block = block[1].split("```")[0]
    head = lambda p: (re.search(p, block, re.M) or [None, ""])[1]
    top = {"LLM": head(r'^model: "(.*?)"'), "quant": head(r'^quant: "(.*?)"'),
           "date": head(r"^date: (\S+)"), "engine": head(r"^engine: \{name: ([^,}]+),"),
           "engine version": head(r'^engine: \{name: [^,}]+, version: "?([^",}]+)"?')}
    rows, best, task = [], {}, ""
    for line in block.splitlines():
        m = re.match(r"^\s+- task: (\S+)", line)
        if m:
            task = m.group(1)
            continue
        m = POINT.match(line)
        if not m:
            continue
        try:
            p = json.loads(m.group(1))   # a measured point is JSON; a failed one is bare words
        except Exception:
            continue
        if "target_ctx" not in p or p.get("runs") == 0:
            continue   # a point that never ran is not a number
        col = "cold" if p["target_ctx"] == 0 else "warm"
        score = 49152 if p["target_ctx"] == 49152 else p["target_ctx"]   # the fixed point wins the column
        k = (top["LLM"], task, col)
        if k not in best or score > best[k][0]:
            best[k] = (score, p)
    out = {}
    for (model, task, col), (score, p) in best.items():
        row = out.setdefault((model, task), dict(top, task=task,
                                                 **{c + " " + c2: None for c in ("tok/s", "ttft")
                                                    for c2 in ("cold", "warm")}))
        row["tok/s " + col], row["ttft " + col] = p.get("decode_tps"), p.get("ttft_s")
    return list(out.values())


def sort_key(r):
    return [-(x if isinstance(x, (int, float)) else -1e9) for x in
            [r["tok/s cold"], r["tok/s warm"]]][0], r["date"] or ""


def table(rows):
    out = ["| " + " | ".join(COLS) + " |", "|" + "|".join(["---"] * len(COLS)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(r.get(c) if r.get(c) is not None else "-") for c in COLS) + " |")
    return "\n".join(out)


def main():
    d = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "BenchmarkLLMs-results")
    if not os.path.isdir(d):
        sys.exit("no such directory: %s" % d)
    rows = [r for f in sorted(glob.glob(os.path.join(d, "*.md"))) for r in rows_for(f)]
    if not rows:
        sys.exit("no posts with a yaml block in %s" % d)
    print("Every post in %s — one row per post x task, sorted by tok/s, highest first.\n"
          "cold = the 0 baseline point; warm = the fixed 48k point (or the highest reached)."
          " '-' = no such number, not zero.\n" % d)
    by_task = {}
    for r in sorted(rows, key=sort_key):
        by_task.setdefault(r["task"], []).append(r)
    for task in sorted(by_task):
        print("### %s\n\n%s\n\n````markdown\n%s\n````\n" % (task, table(by_task[task]), table(by_task[task])))


main()
