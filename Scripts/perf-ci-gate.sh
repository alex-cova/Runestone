#!/usr/bin/env bash
# PR CI:   Scripts/perf-ci-gate.sh 10mb
# Nightly: Scripts/perf-ci-gate.sh 100mb
#          Scripts/perf-ci-gate.sh 500mb
#
# 10 MB short-line fails if keystroke p95 > 16 ms or open+first-layout > 100 ms.
# Larger sizes report the same metrics but do not fail those thresholds unless
# PERF_GATE_FAIL=1 is set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIZE="${1:-10mb}"
SAMPLES="${PERF_KEYSTROKE_SAMPLES:-40}"
KEYSTROKE_MS="${PERF_KEYSTROKE_P95_MS:-16}"
OPEN_MS="${PERF_OPEN_FIRST_LAYOUT_MS:-100}"
FIXTURE_DIR="${PERF_FIXTURE_DIR:-$ROOT/Tools/PerfHarness/Fixtures}"
FIXTURE="$FIXTURE_DIR/short_lines_${SIZE}.txt"

if [[ "$SIZE" == "10mb" ]]; then
  FAIL="${PERF_GATE_FAIL:-1}"
else
  FAIL="${PERF_GATE_FAIL:-0}"
fi

mkdir -p "$FIXTURE_DIR"
if [[ ! -f "$FIXTURE" ]]; then
  python3 "$ROOT/Tools/PerfHarness/generate_fixtures.py" \
    --out "$FIXTURE_DIR" --sizes "$SIZE" --variants short_lines
fi

cd "$ROOT"
TMPDIR_GATE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_GATE"' EXIT

echo "=== PerfHarness CI gate ($SIZE) fixture=$FIXTURE ===" >&2
swift run -c release PerfHarness open "$FIXTURE" --mmap --viewport \
  >"$TMPDIR_GATE/open.csv"
swift run -c release PerfHarness keystroke "$FIXTURE" --at middle --mmap --viewport --samples "$SAMPLES" \
  >"$TMPDIR_GATE/keystroke.csv"
swift run -c release PerfHarness search "$FIXTURE" --pattern func --mmap --viewport \
  >"$TMPDIR_GATE/search.csv"

python3 - "$TMPDIR_GATE/open.csv" "$TMPDIR_GATE/keystroke.csv" "$TMPDIR_GATE/search.csv" \
  "$KEYSTROKE_MS" "$OPEN_MS" "$FAIL" <<'PY'
import sys

def parse(path):
    rows = {}
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("metric,"):
                continue
            parts = line.split(",")
            if len(parts) >= 4:
                try:
                    rows[parts[0]] = float(parts[3])
                except ValueError:
                    pass
    return rows

open_rows = parse(sys.argv[1])
key_rows = parse(sys.argv[2])
search_rows = parse(sys.argv[3])
keystroke_ms_limit = float(sys.argv[4])
open_ms_limit = float(sys.argv[5])
fail = sys.argv[6] == "1"

def seconds(rows, name):
    if name not in rows:
        raise SystemExit(f"missing metric {name} in {rows}")
    return rows[name]

open_s = seconds(open_rows, "open_first_layout")
p95_s = seconds(key_rows, "keystroke_middle_p95")
search_s = search_rows.get("search_literal")

print(
    f"open_first_layout={open_s * 1000:.2f}ms "
    f"(limit {open_ms_limit:.0f}ms)"
)
print(
    f"keystroke_middle_p95={p95_s * 1000:.2f}ms "
    f"(limit {keystroke_ms_limit:.0f}ms)"
)
if search_s is not None:
    print(f"search_literal={search_s * 1000:.2f}ms")

failed = False
messages = []
if p95_s * 1000 > keystroke_ms_limit:
    failed = True
    messages.append(
        f"keystroke p95 {p95_s * 1000:.2f}ms exceeds {keystroke_ms_limit:.0f}ms"
    )
if open_s * 1000 > open_ms_limit:
    failed = True
    messages.append(
        f"open+first-layout {open_s * 1000:.2f}ms exceeds {open_ms_limit:.0f}ms"
    )

if failed:
    text = "; ".join(messages)
    if fail:
        print(f"GATE FAIL: {text}", file=sys.stderr)
        sys.exit(1)
    print(f"GATE WARN (report-only): {text}", file=sys.stderr)
else:
    print("GATE PASS")
PY
