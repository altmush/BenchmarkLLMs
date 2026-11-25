#!/usr/bin/env python3
"""Support tool for benchmarkllms.sh: json | gpulist | mac | wmi | body | post | nameinfo | swap | profile.

Prints "unknown" for anything it cannot read — a missing probe is a field, not a failure.
"""
import collections, json, os, re, statistics, subprocess, sys, hashlib, urllib.parse

U = "unknown"
V = bool(os.environ.get("BML_VERBOSE"))   # debug only: what the web search actually asked for

QUANT_TOKEN = re.compile(r"(?i)(?<![a-z0-9])(iq[0-9][a-z0-9_]*|q[0-9][a-z0-9_]*|n[ki][0-9][a-z0-9_]*|"
                         r"fp8|bf16|awq|gptq|compressed-tensors)(?![a-z0-9])")
TUNING = {"swift", "gsq", "rco", "abliterated", "uncensored", "heretic"}


def jget(d, path):
    for k in path.split("."):
        if isinstance(d, dict):
            d = d.get(k)
        elif isinstance(d, list) and k.isdigit():
            d = d[int(k)] if int(k) < len(d) else None
        else:
            return None
    return d


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=25).stdout
    except Exception:
        return ""


def ident(d):
    """A fork's identity lives in its manifest and its git, not in which endpoint answered first."""
    out = {"name": U, "version": U, "commit": U, "remote": U}
    if not d or not os.path.isdir(d):
        return out
    try:
        j = json.load(open(os.path.join(d, "package.json")))
        out["name"], out["version"] = j.get("name") or U, j.get("version") or U
    except Exception:
        pass
    if out["name"] == U:
        for f, npat, vpat in (("pyproject.toml", r'^name = "(.+)"', r'^version = "(.+)"'),
                              ("Cargo.toml", r'^name = "(.+)"', None),
                              ("go.mod", r"^module (\S+)", None)):
            try:
                txt = open(os.path.join(d, f)).read()
                m = re.search(np, txt, re.M) if (np := npat) else None
                if m:
                    out["name"] = m.group(1)
                    if vpat and (v := re.search(vpat, txt, re.M)):
                        out["version"] = v.group(1)
                    break
            except Exception:
                pass
    g = lambda *a: run(["git", "-C", d] + list(a)).strip()
    out["commit"] = g("rev-parse", "--short", "HEAD") or U
    out["remote"] = (g("remote", "get-url", "origin") or U).rstrip("/")
    return out


def gpulist():
    """Vendor CLI first: fastfetch reports no VRAM for NVIDIA, and its card order is not NVML order."""
    out = []
    csv = run(["nvidia-smi", "--query-gpu=index,name,uuid,memory.total,driver_version",
               "--format=csv,noheader,nounits"])
    if csv.strip():
        for line in csv.strip().splitlines():
            p = [x.strip() for x in line.split(",")]
            if len(p) >= 4 and p[3].isdigit():
                out.append({"id": int(p[0]), "model": p[1], "vram_gb": round(int(p[3]) / 1024, 1),
                            "uuid": p[2][:8] if os.environ.get("BENCHMARKLLMS_UUID") != "full" else p[2],
                            "driver": p[4] if len(p) > 4 else None, "source": "nvidia-smi"})
        return out
    j = run(["rocm-smi", "--showproductname", "--showmeminfo", "vram", "--json"])
    if j.strip():
        try:
            for card, v in json.loads(j).items():
                if not isinstance(v, dict):
                    continue
                tot = jget(v, "total") or jget(v, "total_bytes")
                tot = int(tot) if str(tot).isdigit() else 0
                out.append({"id": card, "model": jget(v, "productname") or U,
                            "vram_gb": round(tot / 2**30, 1) if tot else None,
                            "uuid": jget(v, "deviceid"), "driver": None, "source": "rocm-smi"})
        except Exception:
            pass
        if out:
            return out
    for line in run(["vulkaninfo", "--summary"]).splitlines():
        if "apiVersion" in line:
            out.append({"id": len(out), "model": line.split(":")[0].strip(), "vram_gb": None,
                        "uuid": None, "driver": None, "source": "vulkaninfo"})
    return out


def mac():
    out = []
    try:
        d = json.loads(run(["system_profiler", "SPDisplaysDataType", "-json"]))
    except Exception:
        return out
    for item in (jget(d, "spdisplays_data_type") or []):
        for g in (jget(item, "_arrays_") or []):
            vram = jget(g, "spdisplays_vram")
            gb = None
            if vram:
                n = "".join(c for c in str(vram) if c.isdigit())
                if n:
                    gb = round(int(n) / (1024 if "MB" in str(vram) else 1), 1)
            out.append({"id": len(out), "model": jget(g, "spdisplays_model") or U, "vram_gb": gb,
                        "uuid": None, "driver": jget(g, "spdisplays_metaltier") or "unified memory",
                        "source": "system_profiler"})
    return out


def wmi():
    """AdapterRAM is a DWORD and caps at 4 GB, so it is not trusted for VRAM."""
    out = []
    ps = run(["powershell.exe", "-NoProfile", "-Command",
              "Get-CimInstance Win32_VideoController | Select-Object -Property Name,AdapterRAM,DriverVersion | ConvertTo-Json -Compress"])
    try:
        d = json.loads(ps)
    except Exception:
        return out
    for g in (d if isinstance(d, list) else [d]):
        ram = g.get("AdapterRAM")
        out.append({"id": len(out), "model": g.get("Name") or U,
                    "vram_gb": round(ram / 2**30, 1) if isinstance(ram, int) and ram else None,
                    "uuid": None, "driver": g.get("DriverVersion"),
                    "source": "WMI AdapterRAM (caps at 4 GB)"})
    return out


def body(seed_file, filler_file, target, model, maxtokens, temp, seed, engine, task, sha, runno):
    seed_text = open(seed_file).read().strip()
    filler = open(filler_file).read().strip()
    # shortcut: no tokenizer here, so padding is approximate and the ACTUAL context is read
    # back from usage.prompt_tokens. upgrade if exact ladder points ever matter.
    reps = max(0, int((int(target) - 150) / max(len(filler) // 4, 1)))
    prompt = seed_text + ("\n\n" + filler) * reps
    req = {"model": model, "messages": [{"role": "user", "content": prompt}],
           "max_tokens": int(maxtokens), "temperature": float(temp), "seed": int(seed),
           "stream": True, "stream_options": {"include_usage": True}}
    # The ladder is only comparable if every request is cold. Only send the engine's own
    # cache-buster field, so a strict OpenAI-compatible validator never sees an unknown key.
    salt = "cold-%s-%s-%s" % (sha, task, runno)
    if engine in ("vllm", "sglang"):
        req["cache_salt"] = salt
    elif engine == "llama.cpp":
        req["cache_id"] = salt
    return json.dumps(req)


COLS = ("task target sha model engine pt ct ttft total runno code draft accepted "
        "e_prompt_ms e_pred_ms").split()
IDX_CODE = COLS.index("code")


def rates(row):
    """Engine-side timings when the engine reports them (source: engine), else the timings
    around the request (source: client). They are not the same measurement, so say which."""
    pt, ct = row["pt"], row["ct"]
    pm, pmsec = row["e_prompt_ms"], row["e_pred_ms"]
    if all(v not in ("", U) and float(v) > 0 for v in (pm, pmsec)):
        pre = round(int(pt) * 1000 / float(pm), 1) if pt not in ("", U) and int(pt) > 0 else U
        dec = round(int(ct) * 1000 / float(pmsec), 1) if ct not in ("", U) and int(ct) > 0 else U
        return pre, dec, round(float(pm) / 1000, 3), round((float(pm) + float(pmsec)) / 1000, 2), "engine"
    ttft, total = float(row["ttft"]), float(row["total"])
    pre = round(int(pt) / max(ttft, 1e-9), 1) if pt not in (U, "") and int(pt) > 0 else U
    dec = (round(int(ct) / max(total - ttft, 1e-9), 1)
           if ct not in (U, "") and int(ct) > 0 and total > ttft else U)
    return pre, dec, ttft, total, "client"  # same shape as the engine branch above


def stats(vals):
    vs = [float(v) for v in vals if v not in (U, "") and float(v) > 0]
    if not vs:
        return U, 0
    return (round(statistics.median(vs), 1), round(statistics.stdev(vs), 2) if len(vs) > 1 else 0)



def pub_endpoint(u):
    """Home network layout is personal data. On the public block, keep the port, drop the host."""
    if os.environ.get("BENCHMARKLLMS_ENDPOINT") == "full":
        return u
    netloc = u.split("://")[-1].split("/")[0]
    host = netloc.rsplit(":", 1)[0]
    if host in ("127.0.0.1", "localhost", "::1", ""):
        return u
    return "%s (host redacted)" % netloc.rsplit(":", 1)[-1]


def guessed(src):
    """A guess must never look like a fact: a fork answers the same endpoints as its upstream."""
    return {
        "probe": "  (identity guessed from endpoints — verify)",
        "alias": "  (the router's nickname, not a model name — the questionnaire asks the human)",
        "profile": "  (from your saved answers)",
        "search": "  (likely)",   # a web search match is a strong guess, not a fact: keep the label
    }.get(src, "")


def mednum(rows, key):
    vals = [float(r[key]) for r in rows if r[key] not in (U, "")]
    return round(statistics.median(vals), 1) if vals else U
def num(v):
    return U if v in (U, "") else (int(float(v)) if str(v).replace(".", "", 1).isdigit() else v)

def headline_numbers(runs):
    """The two numbers a reader compares: the fixed ladder point per task (48k = 49152, or the
    highest point actually reached), then the median across tasks. Same rule as the history table."""
    best = {}
    for (task, target, sha), rows in runs.items():
        ok = [dict(zip(COLS, r)) for r in rows if len(r) == len(COLS) and r[IDX_CODE] == "200"]
        if not ok:
            continue
        score = 49152 if int(target) == 49152 else int(target)
        if task not in best or score > best[task][0]:
            best[task] = (score, ok)
    if not best:
        return {"tps": U, "ttft": U}
    dec = [x[1] for score, rows in best.values() for x in [rates(r) for r in rows] if x[1] != U]
    tt = [x[2] for score, rows in best.values() for x in [rates(r) for r in rows] if x[2] != U]
    return {"tps": stats(dec)[0], "ttft": "%s s" % stats(tt)[0] if dec or tt else U}


def short_name(model):
    """The subreddit title wants the family name, not the filename: `Qwen3.8`, not
    `Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_XXS`. First name token that is not a quant, a tuner
    or an uploader tag."""
    for t in re.split(r"[-_]", re.sub(r"\.[gG][gG][uU][fF]$", "", model or "")):
        if t and not QUANT_TOKEN.match(t) and t.lower() not in TUNING and not re.fullmatch(r"[a-zA-Z]+[0-9]+[a-zA-Z]*", t):
            return t
    return model or U


def short_gpu(name, vram):
    """`NVIDIA GeForce RTX 3060` is `3060` in a title; the vendor prefix is a reader's dead weight."""
    n = re.search(r"(?i)\b(v\d+[a-z]?|mi\d+[a-z]*|a\d+[a-z]*|h\d+[a-z]*|\d{3,4}[a-z]?)\b", name or "")
    return n.group(0) if n else ((name or U).split()[0] if (name or "").split() else U)


def title_gpus(gpus):
    """Cards of the same kind collapse into one count, biggest card first:
    `V100(16gb) + 2x3060s(12gb)`. A title is prose, so it gets the tidy form; the yaml block keeps
    the exact numbers."""
    groups = {}
    for g in gpus:
        v = g.get("vram_gb")
        try:
            v = int(float(v)) if str(v).replace(".", "", 1).isdigit() else v
        except Exception:
            pass
        groups[(short_gpu(g.get("model"), None), v)] = groups.get((short_gpu(g.get("model"), None), v), 0) + 1
    if not groups:
        return U
    return " + ".join(
        "%s%s(%s%s)" % ("%dx" % n if n > 1 else "", base + ("s" if n > 1 else ""),
                        n and v, "gb")
        for (base, v), n in sorted(groups.items(), key=lambda x: (
            -(x[0][1] if isinstance(x[0][1], int) else -1), -x[1], x[0][0])))


def build_post(metafile, runsfile):
    m = collections.defaultdict(lambda: U)   # a field nobody filled is `unknown`, not a crash
    for line in open(metafile):
        p = line.rstrip("\n").split("\t")
        m[p[0]] = p[1] if len(p) > 1 else U
    runs = {}
    tables = []   # what the ladder measured, for the section a human reads
    for line in open(runsfile):
        p = line.rstrip("\n").split("\t")
        if len(p) < len(COLS):
            continue
        runs.setdefault((p[0], p[1], p[2]), []).append(p)
    A = []
    a = A.append
    tldr = {}
    gpus = json.loads(m["gpus"]) if str(m["gpus"]).strip().startswith("[") else []
    warm = headline_numbers(runs)
    engine_name = (m["engine"] or U)
    engine_name = engine_name[0].upper() + engine_name[1:] if engine_name not in (U, "") else engine_name
    tps = warm["tps"]
    tps = "~%s TOK/s" % int(float(tps)) if str(tps).replace(".", "", 1).isdigit() else tps
    a("# Reddit Post Title: %s - %s - %s - %s - %s"
      % (short_name(m["model"]), m["quant"], engine_name, tps, title_gpus(gpus)))
    a("")
    a("# TLDR")
    a("")
    a("## Model")
    a("MODEL: %s%s" % (m["model"], guessed(m["model_source"])))
    a("QUANT: %s" % m["quant"])
    a("Fine Tuning: %s" % m["fine_tuning"])
    a("HF LINK: %s%s" % (m["hf"], guessed(m["hf_source"])))
    a("Warm TTFT: %s" % warm["ttft"])
    a("Warm TOK/s: %s" % warm["tps"])
    a("")
    a("## System")
    a("OS: %s" % m["os"])
    for i, g in enumerate(gpus):
        a("GPU#%s: %s - %s GB" % (g.get("id", i), g.get("model") or U,
                                  g.get("vram_gb") if g.get("vram_gb") is not None else U))
    if not gpus:
        a("GPU#0: %s" % U)
    a("CPU: %s" % m["cpu"])
    a("RAM: %s" % m["ram"])
    a("")
    a("## Inference")
    a("ENGINE: %s%s" % (m["engine"], guessed(m["engine_source"])))
    a("ENGINE VERSION: %s" % m["engine_version"])
    a("ENGINE COMMIT: %s" % (m["engine_commit"] or U))
    a("DRAFTER: %s" % m["drafter"])
    a("FLAGS: %s" % m["flags"])
    a("")
    a("## Harness")
    a("Harness: %s%s" % (m["harness_name"] or U, guessed(m["harness_source"])))
    a("Harness Tools: %s" % (m["harness_tools"] or U))
    a("Harness Commit: %s" % (m["harness_commit"] or U))
    a("")
    a("## Additional")
    a('Additional Notes (human): %s' % (m.get('notes') or ''))
    pos = len(A) + 1   # the results table is written here once the ladder has been tallied below
    a("")
    # when the run starts, when it ends, and what it cost the user
    a("## Time Results")
    a("Benchmark Start Time: %s" % (m["bench_start"] or U))
    a("Benchmark End Time: %s" % (m["bench_end"] or U))
    a("Total Time for Benchmark: %s" % (m["total_time_s"] or U))
    a("")
    a("```yaml")
    a("schema: %s" % m["schema"])
    a("date: %s" % m["date"])
    a("model: %s" % json.dumps(m["model"]))
    a("model_source: %s" % json.dumps(m["model_source"]))
    a("quant: %s" % json.dumps(m["quant"]))
    a("fine_tuning: %s" % json.dumps(m["fine_tuning"]))
    a("hf: %s" % json.dumps(m["hf"]))
    flags = m["flags"] if str(m["flags"]).startswith("[") else json.dumps(m["flags"])
    a("engine: {name: %s, version: %s, commit: %s, remote: %s, flags: %s, drafter: %s}"
      " identity_source: %s}"
      % (m["engine"], json.dumps(m["engine_version"]), json.dumps(m["engine_commit"]),
         json.dumps(m["engine_remote"]), flags, json.dumps(m["drafter"]),
         json.dumps(m["engine_source"])))
    a("harness: {name: %s, version: %s, commit: %s, tools: %s, model_alias: %s, endpoint: %s,"
      " self_contention: %s, identity_source: %s}"
      % (m["harness_name"] or U, json.dumps(m["harness_version"]), json.dumps(m["harness_commit"]),
         json.dumps([t for t in (m["harness_tools"] or "").split() if t]),
         json.dumps(m["harness_model_alias"] or None), json.dumps(pub_endpoint(m["endpoint"])),
         json.dumps(bool(m["self_contention"])), json.dumps(m["harness_source"])))
    a("os: %s" % json.dumps(m["os"]))
    a("cpu: %s" % json.dumps(m["cpu"]))
    a("ram: %s" % json.dumps(m["ram"]))
    a("gpus: %s" % (json.dumps(gpus) if str(m["gpus"]).strip().startswith("[") else "[]"))
    a("measurement: {source: %s, batch: %s, prefix_cache: %s, temperature: %s, seed: %s, "
      "n: %s, statistic: %s, warmup: %s, max_tokens: %s}"
      % (m["source"], m["batch"], m["prefix_cache"], m["temperature"], m["seed"], m["n"],
         m["statistic"], m["warmup"], m["max_tokens"]))
    a("model_max_context: %s" % m["model_max_context"])
    a("ladder: [%s]" % m["ladder"])
    a("bench_start: %s" % json.dumps(m["bench_start"]))
    a("bench_end: %s" % json.dumps(m["bench_end"]))
    a("total_time_s: %s" % m["total_time_s"])
    a('runs: []' if not runs else 'runs:')
    for (task, target, sha), rows in sorted(runs.items()):
        a("  - task: %s" % task)
        a("    seed_sha256: %s" % sha)
        a("    points:")
        got = [dict(zip(COLS, r)) for r in rows if len(r) == len(COLS) and r[IDX_CODE] == "200"]
        if not got:
            codes = sorted({r[IDX_CODE] for r in rows if len(r) == len(COLS) and r[IDX_CODE]})
            why = "skipped" if not codes else ",".join(codes)
            a("      - {target_ctx: %s, %s: %s, runs: 0}"
              % (target, "skipped" if not codes else "error", ",".join(codes) or "no data"))
            tables.append((task, int(target), {"runs": 0, "source": "no number — %s" % why}))
            continue
        rr = [rates(r) for r in got]
        pre = stats([x[0] for x in rr]); dec = stats([x[1] for x in rr])
        tt = stats([x[2] for x in rr]); tl = stats([x[3] for x in rr])
        srcs = sorted({x[4] for x in rr})
        point = {"target_ctx": int(target), "actual_ctx": num(mednum(got, "pt")),
                 "prefill_tps": pre[0], "decode_tps": dec[0], "ttft_s": tt[0], "total_s": tl[0],
                 "out_tokens": num(mednum(got, "ct")), "ttft_stdev_s": tt[1],
                 "total_stdev_s": tl[1], "runs": len(got), "source": "/".join(srcs)}
        acc = [int(r["accepted"]) / int(r["draft"])
               for r in got if r["draft"] not in (U, "") and r["accepted"] not in (U, "")
               and int(r["draft"]) > 0]
        tldr.setdefault(task, {})[int(target)] = dec[0]
        tables.append((task, int(target), point))
        if acc:  # only engines that report their own draft counters can fill these two
            point["draft_tokens"] = round(statistics.median(
                [int(r["draft"]) for r in got if r["draft"] not in (U, "")]), 1)
            point["acceptance_rate"] = round(statistics.median(acc), 3)
        a("      - " + json.dumps(point))
    if tables:
        rows = ["", "## Results", "",
                "| task | ladder | actual ctx | prefill tok/s | decode tok/s | TTFT s | total s | stdev s | runs | source |",
                "|---|---|---|---|---|---|---|---|---|---|"]
        for t, tgt, p in sorted(tables, key=lambda x: (x[0], x[1])):
            rows.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s%s |" % (
                t, tgt, p.get("actual_ctx") or U, p.get("prefill_tps") or U, p.get("decode_tps") or U,
                p.get("ttft_s") or U, p.get("total_s") or U,
                p.get("ttft_stdev_s") if p.get("ttft_stdev_s") != "" else U, p.get("runs") or 0,
                p.get("source") or U,
                " draft %s, accepted %s" % (p["draft_tokens"], p["acceptance_rate"])
                if p.get("draft_tokens") else ""))
        A[pos:pos] = rows + [""]
    for t in sorted(tldr):
        pts = ", ".join("~%s tok/s @ %dk" % (v, k // 1024) for k, v in sorted(tldr[t].items())
                        if v != U)
        A[4:4] = ["- %s decode: %s" % (t.capitalize(), pts or "no data"), ""]
    a('quality: {task: general, pass: 0, of: 0}')
    a('notes: %s' % json.dumps(m.get('notes') or ''))
    a("```")
    a("")
    a("Benchmarked with [BenchmarkLLMs](https://github.com/altmush/BenchmarkLLMs)")
    post_text = "\n".join(A)
    return post_text


def post(metafile, runsfile, mode=""):
    body = build_post(metafile, runsfile)
    if mode != "reply":
        print(body)
        return
    # The shape a post run ends with: the numbers to read, the same thing fenced to paste, and the
    # questions nobody answered yet (a guessed source is the post saying "check me").
    m = dict(l.rstrip("\n").split("\t", 1) for l in open(metafile))
    q = [(f, v) for f, v in sorted(m.items()) if f.endswith("_source") and v[0] in ("p", "a", "u")]
    print("Congratulations! Your benchmark is ready!")
    print("\n## Human Readable Results\n\n%s\n" % body.split("```yaml")[0].rstrip())
    print("Here is your results in markdown format to easily post to "
          "[/r/BenchmarkLLMs](https://www.reddit.com/r/BenchmarkLLMs/)\n")
    print("````markdown\n%s\n````" % body)   # four backticks: the post contains a fenced yaml block
    if q:
        print("\n## Follow Up questions")
        for f, v in q:
            print("- %s: %s (source: %s)" % (f[:-7], m.get(f[:-7], "") or "unknown", v))
    else:
        print("\nNo follow-up questions — every field was confirmed by a flag, a file, or the engine.")


def nameinfo(name):
    """On this subreddit the filename IS the spec sheet: quant and tuning ride in it.
    Prints tab lines (quant, tuning); empty value = not in the name, so the questionnaire asks."""
    stem = re.sub(r"\.[gG][gG][uU][fF]$", "", name)
    quant = QUANT_TOKEN.search(stem)
    tune = [t for t in re.split(r"[-_]", stem) if t.lower() in TUNING]
    print("quant\t%s" % (quant.group(1) if quant else ""))
    print("tuning\t%s" % " ".join(dict.fromkeys(tune)))


def swap(config, alias):
    """A llama-swap selector names the file it boots, so an alias can be resolved without asking —
    but only if the launcher says so in plain text. Space-separated candidates; several = a question."""
    out = []
    try:
        txt = open(config).read()
    except Exception:
        return out
    m = re.search(r'^ *"?%s"?: *$' % re.escape(alias), txt, re.M)
    if not m:
        return out
    block = txt[m.end():]
    end = re.search(r"^\S", block, re.M)   # the alias's own block ends at the next top-level key
    for f in re.findall(r'^ *(?:cmd|yaml|config|path): *"?([^"\s]+)"?', block[:end.start()] if end else block, re.M):
        try:
            for line in open(os.path.expanduser(f)).read().splitlines():
                if line.strip().startswith("#"):
                    continue   # a commented-out model is yesterday's answer, not this run's
                for g in re.findall(r'(/\S+)\.gguf', line):
                    out.append(os.path.basename(g))
        except Exception:
            pass   # container-side paths are not readable from here; the questionnaire handles those
    return list(dict.fromkeys(out))


def profile(action, path, key, *pairs):
    """Questionnaire answers, remembered per endpoint+alias so a human only answers once.
    Flags still beat them: a saved answer is a guess with an expiry date."""
    try:
        d = json.load(open(path))
    except Exception:
        d = {}
    if action == "get":
        for k, v in sorted((d.get(key) or {}).items()):
            print("%s\t%s" % (k, v))
        return
    e = d.setdefault(key, {})
    for p in pairs:
        f, _, v = p.partition("=")
        if v and v != U:
            e[f] = v
    try:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)   # the profile dir is ours to create
        json.dump(d, open(path, "w"), indent=1)
        print("saved %s answers for %s" % (len(e), key))
    except Exception:
        print(U)


def hfsearch(name):
    """A filename is not a repo id, so ask huggingface.co's own search API — but read the filename as
    a spec sheet first: a token like `SC117` is an org, so it goes in as an author filter, and the
    quant and tuner words are not part of most repo names, so they rank candidates instead of
    identifying them. A candidate must carry every word the filename names; among those, the one
    carrying the most of them wins, an exact-name candidate is `exact`, and the rest say so."""
    stem = re.split(r"\.[gG][gG][uU][fF]$", name)[0]
    m = QUANT_TOKEN.search(stem)
    quant = m.group(1) if m else ""
    toks = [t for t in re.split(r"[-_]", stem) if t]        # a dot belongs to a name (Qwen3.8); hyphens and underscores split fields
    words = {t.lower() for t in toks}
    qsegs = set(quant.lower().split("_")) if quant else set()
    orgs = [t for t in toks if t.lower() not in qsegs and re.fullmatch(r"[A-Za-z]{2,}[0-9]{2,}[A-Za-z]*", t)]
    tune = {t.lower() for t in toks if t.lower() in TUNING}
    family = [t for t in toks if t.lower() not in qsegs and t not in orgs and t.lower() not in tune]
    if not family:
        return   # nothing left that names a model: a size or a tag alone would search the whole site
    q = urllib.parse.quote("-".join(family[:4]))
    urls = ["https://huggingface.co/api/models?search=%s&limit=10" % q]
    urls += ["https://huggingface.co/api/models?search=%s&author=%s&limit=10" % (q, urllib.parse.quote(o))
             for o in orgs[:2]]   # the org named in the filename is the strongest clue there is
    seen, hits = set(), []
    for u in urls:
        try:
            for h in json.loads(run(["curl", "-fsS", "--retry", "2", "--retry-delay", "2", "--max-time", "20", u])):
                rid = (h.get("id") or "").strip("/")
                if rid and rid.lower() not in seen:
                    seen.add(rid.lower())
                    hits.append(rid)
        except Exception as e:
            if V:
                print("search %s: %s" % (u, e), file=sys.stderr)   # offline, or the API answered nothing
    want = {w for w in words if w not in {o.lower() for o in orgs}}   # every word the filename names, the org aside
    ranked = []
    for rid in hits:
        parts = {w for part in rid.lower().split("/") for w in re.split(r"[-_]", part) if w}
        if not {t.lower() for t in family}.issubset(parts):
            continue   # a hit missing one family word is a different model wearing the name
        name_part = rid.lower().split("/")[-1]
        exact = (not want.issubset(parts)) or want.issubset({w for w in re.split(r"[-_]", name_part) if w})
        org_ok = (not orgs) or rid.lower().split("/")[0] in {o.lower() for o in orgs}
        score = len(words & parts) + (2 if org_ok and orgs else 0) + (1 if len(parts) == len(words) else 0)
        ranked.append((-score, 0 if exact else 1, rid, exact))
    for _, _, rid, exact in sorted(ranked)[:4]:
        print("https://huggingface.co/%s\t%s" % (rid, "exact" if exact else "likely"))


def hf_tree(repo, sub=""):
    try:   # the quant folder is the one worth listing: two repos can share a name and differ only inside it
        return json.loads(run(["curl", "-fsS", "--retry", "2", "--retry-delay", "2", "--max-time", "20",
                                "https://huggingface.co/api/models/%s/tree/main%s" %
                                (repo, "/" + sub if sub else "")]))
    except Exception:
        return []   # cannot look, cannot claim


def main():
    cmd = sys.argv[1]
    if cmd == "json":
        path = sys.argv[2] if len(sys.argv) > 2 else ""
        try:
            d = json.loads(sys.stdin.read())
        except Exception:
            d = None
        if isinstance(d, list) and d and isinstance(d[0], dict) and "type" in d[0]:
            parts = path.split(".")
            d = next((x.get("result") for x in d if x.get("type") == parts[0]), None)
            path = ".".join(parts[1:])
        v = jget(d, path) if path else d
        print(U if v in (None, "") else (json.dumps(v) if isinstance(v, (list, dict)) else v))
    elif cmd == "body":
        print(body(*sys.argv[2:13]))
    elif cmd in ("gpulist", "mac", "wmi"):
        print(json.dumps(globals()[cmd]()))
    elif cmd == "ident":
        print(json.dumps(ident(sys.argv[2])))
    elif cmd == "nameinfo":
        nameinfo(*sys.argv[2:])
    elif cmd == "swap":
        print(" ".join(swap(*sys.argv[2:])))
    elif cmd == "hfsearch":
        hfsearch(*sys.argv[2:])
    elif cmd == "profile":
        profile(*sys.argv[2:])
    elif cmd == "post":
        post(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "")


main()
