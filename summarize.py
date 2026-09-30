"""Summarize a run_all.sh JSONL file into a markdown table.

Per system/scope: upstream calls admitted in each test (10 = exact,
<10 conservative, >10 overspend), and the burst's spend as a multiple of
the $0.0045 budget. Burst + wave2 are cumulative on one budget.
"""
import json
import sys
from collections import defaultdict

LIMIT_CALLS = 10
rows = defaultdict(dict)
skipped = 0
for path in sys.argv[1:]:  # later files (reruns) override earlier rows for the same test
    for line in open(path):
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            skipped += 1
            continue
        rows[(r["system"], r["scope"])][r["test"]] = r["result"].get("upstream_calls")


def cell(v):
    return "–" if v is None else str(v)


print("| System | Budget scope | burst30 → upstream | +wave2 | total on budget | seq15 | stream burst30 | +wave2 | stream seq15 | worst overspend |")
print("|---|---|---|---|---|---|---|---|---|---|")
for (sysname, scope), t in rows.items():
    b, w = t.get("burst30"), t.get("wave2")
    sb, sw = t.get("stream_burst30"), t.get("stream_wave2")
    totals = [x for x in ((b or 0) + (w or 0) if b is not None else None,
                          (sb or 0) + (sw or 0) if sb is not None else None,
                          t.get("seq15"), t.get("stream_seq15")) if x is not None]
    worst = max(totals) if totals else None
    over = "none" if worst is not None and worst <= LIMIT_CALLS else (f"{worst / LIMIT_CALLS:.1f}× budget" if worst else "–")
    print(f"| {sysname} | {scope} | {cell(b)} | {cell(w)} | {cell((b or 0) + (w or 0) if b is not None else None)} | "
          f"{cell(t.get('seq15'))} | {cell(sb)} | {cell(sw)} | {cell(t.get('stream_seq15'))} | {over} |")

if skipped:
    print(f"\n_{skipped} unparsable line(s) skipped (a system crashed mid-run); see the rerun file._")
