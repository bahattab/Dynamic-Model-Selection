#!/usr/bin/env bash
# Summarise the DMS route log for "DMS status" (macOS / Linux). Reads only event names, never prompts.
# Usage: bash scripts/dms-report.sh [log-file]
#
# Events: hook   inject | skip | trigger | on | off | mod (the mod handled the prompt)
#         mod    pass | switch <tier> main | recommend <tier> main | judge ... |
#                auto <tier> subagent | keep <tier> subagent | handpick
#         model  route <tier> <subagent|session>
set -u
STATE_DIR="${DMS_STATE_DIR:-$HOME/.config/dms}"
LOG="${1:-$STATE_DIR/routes.log}"

if [ -f "$STATE_DIR/disabled" ]; then mode="off (DMS off)"
elif [ -f "$STATE_DIR/enabled" ]; then mode="on (DMS on)"
else mode="${DMS_DEFAULT:-on} (default)"; fi
echo "Automatic routing: $mode"
if [ -f "$STATE_DIR/mod-active" ] && [ -n "$(find "$STATE_DIR/mod-active" -mmin -30 2>/dev/null)" ]; then
  echo "Engine: DMS mod (routing in code)"
else
  echo "Engine: hook + skill"
fi

if [ ! -s "$LOG" ]; then
  echo "Route log: empty ($LOG)"
  exit 0
fi

awk '
  { first = (NR == 1 ? $1 : first); last = $1; ev[$2]++ }
  $2 == "route"  { route[$3]++ }
  $2 == "switch" { sw[$3]++ }
  $2 == "auto"   { auto[$3]++ }
  END {
    printf "Log: %s .. %s\n", first, last
    printf "Hook: inject=%d skip=%d trigger=%d mod=%d on=%d off=%d\n", ev["inject"], ev["skip"], ev["trigger"], ev["mod"], ev["on"], ev["off"]
    if (ev["mod"] + ev["pass"] + ev["switch"] + ev["recommend"] + ev["auto"] + ev["keep"] > 0) {
      printf "Mod: switch=%d (opus=%d sonnet=%d haiku=%d) recommend=%d judge-calls=%d handpick=%d\n", ev["switch"], sw["deep"], sw["balanced"], sw["fast"], ev["recommend"], ev["judge"], ev["handpick"]
      printf "Mod subagents: cheaper=%d (sonnet=%d haiku=%d) kept-as-set=%d\n", ev["auto"], auto["balanced"], auto["fast"], ev["keep"]
    }
    printf "Model routes: %d", ev["route"]
    if (ev["route"]) printf " (haiku=%d sonnet=%d opus=%d)", route["haiku"], route["sonnet"], route["opus"]
    printf "\n"
    prompts = ev["inject"] + ev["skip"] + ev["trigger"] + ev["mod"]
    changed = ev["route"] + ev["switch"] + ev["auto"]
    if (prompts) printf "Changed share of prompts seen: %.0f%%\n", 100 * changed / prompts
  }
' "$LOG"
