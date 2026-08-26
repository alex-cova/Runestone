#!/bin/bash
# Record Instruments traces of MacExample opening a large fixture.
#
# Usage:
#   Tools/PerfHarness/record-open-instruments.sh [fixture-path]
#
# Default fixture: Tools/PerfHarness/Fixtures/short_lines_500mb.txt
# Templates: Time Profiler, Allocations, VM Tracker.
# Filter signposts: subsystem Runestone, category Performance.
#
# Headless xctrace may fail without GUI/TCC. If so, open Instruments.app,
# choose those templates, and launch:
#   Example/MacExample with argument --open <fixture>

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="${1:-$ROOT/Tools/PerfHarness/Fixtures/short_lines_500mb.txt}"
OUT_DIR="${2:-$ROOT/Tools/PerfHarness/Instruments}"
mkdir -p "$OUT_DIR"

if [[ ! -f "$FIXTURE" ]]; then
  echo "Fixture not found: $FIXTURE" >&2
  echo "Generate with:" >&2
  echo "  python3 Tools/PerfHarness/generate_fixtures.py --out Tools/PerfHarness/Fixtures --sizes 500mb --variants short_lines" >&2
  exit 1
fi

cd "$ROOT/Example"
xcodebuild -scheme MacExample -configuration Release -derivedDataPath "$OUT_DIR/DerivedData" build

APP=$(find "$OUT_DIR/DerivedData" -name 'MacExample.app' -print -quit)
if [[ -z "$APP" ]]; then
  echo "MacExample.app not found after build" >&2
  exit 1
fi

BINARY="$APP/Contents/MacOS/MacExample"

record() {
  local template="$1"
  local name="$2"
  local trace="$OUT_DIR/${name}.trace"
  rm -rf "$trace"
  echo "Recording $template -> $trace"
  xctrace record --template "$template" --output "$trace" --launch -- "$BINARY" --open "$FIXTURE" || {
    echo "xctrace failed for $template (often GUI/TCC). Record the same launch in Instruments.app." >&2
  }
}

record "Time Profiler" "open-time-profiler"
record "Allocations" "open-allocations"
record "VM Tracker" "open-vm-tracker"

echo "Traces in $OUT_DIR"
echo "Signposts: subsystem Runestone / category Performance"
