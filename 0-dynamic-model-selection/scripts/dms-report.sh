#!/usr/bin/env bash
# Summarise the DMS route log for "DMS status" (macOS / Linux). Reads only event names, never prompts.
# Usage: bash scripts/dms-report.sh [log-file]
set -u
STATE_DIR="${DMS_STATE_DIR:-$HOME/.config/dms}"
LOG="${1:-$STATE_DIR/routes.log}"

if [ -f "$STATE_DIR/disabled" ]; then mode="off (DMS off)"
elif [ -f "$STATE_DIR/enabled" ]; then mode="on (DMS on)"
else mode="${DMS_DEFAULT:-on} (default)"; fi
echo "Automatic routing: $mode"

if [ ! -s "$LOG" ]; then
  echo "Route log: empty ($LOG)"
  exit 0
fi

awk '
  { first = (NR == 1 ? $1 : first); last = $1 }
  $2 == "route" { routes++; tier[$3]++; how[$4]++; next }
  { ev[$2]++ }
  END {
    printf "Log: %s .. %s\n", first, last
    printf "Hook: inject=%d skip=%d trigger=%d on=%d off=%d\n", ev["inject"], ev["skip"], ev["trigger"], ev["on"], ev["off"]
    printf "Routes: %d", routes
    if (routes) {
      printf " (haiku=%d sonnet=%d opus=%d; subagent=%d session=%d)", tier["haiku"], tier["sonnet"], tier["opus"], how["subagent"], how["session"]
    }
    printf "\n"
    prompts = ev["inject"] + ev["skip"] + ev["trigger"]
    if (prompts) printf "Routed share of prompts seen by the hook: %.0f%%\n", 100 * routes / prompts
  }
' "$LOG"
