#!/usr/bin/env bash
# Summarise the DMS route log for "DMS status" (macOS / Linux). Reads only event names, never prompts.
# Usage: bash scripts/dms-report.sh [log-file ...]   (default: routes.log and mod.log)
#
# Events: routes.log  hook   inject | skip | trigger | on | off | mod (the mod handled the prompt)
#                     model  route <tier> <subagent|session>
#         mod.log     mod    pass [cooldown|judged] | switch <tier> main | revert <tier> main |
#                            recommend <tier> main | judge <tier> <conf> | judge none|error|unreadable |
#                            handpick | off | auto <tier> subagent | keep <tier> subagent
set -u
STATE_DIR="${DMS_STATE_DIR:-$HOME/.config/dms}"
if [ "$#" -gt 0 ]; then LOGS=("$@"); else LOGS=("$STATE_DIR/routes.log" "$STATE_DIR/mod.log"); fi

if [ -f "$STATE_DIR/disabled" ]; then mode="off (DMS off)"
elif [ -f "$STATE_DIR/enabled" ]; then mode="on (DMS on)"
else mode="${DMS_DEFAULT:-on} (default)"; fi
echo "Automatic routing: $mode"
if [ -d "$STATE_DIR/mod" ] && [ -n "$(find "$STATE_DIR/mod" -type f -mmin -30 2>/dev/null | head -n 1)" ]; then
  echo "Engine: DMS mod (routing in code) in a session active in the last 30 minutes"
else
  echo "Engine: hook + skill"
fi

present=()
for f in "${LOGS[@]}"; do [ -s "$f" ] && present+=("$f"); done
if [ "${#present[@]}" -eq 0 ]; then
  echo "Route log: empty (${LOGS[*]})"
  exit 0
fi

awk '
  { if (first == "" || $1 < first) first = $1; if ($1 > last) last = $1; ev[$2]++ }
  $2 == "route"  { route[$3]++ }
  $2 == "switch" { sw[$3]++ }
  $2 == "auto"   { auto[$3]++ }
  END {
    printf "Log: %s .. %s\n", first, last
    printf "Hook: inject=%d skip=%d trigger=%d mod=%d on=%d off=%d\n", ev["inject"], ev["skip"], ev["trigger"], ev["mod"], ev["on"], ev["off"]
    if (ev["mod"] + ev["pass"] + ev["switch"] + ev["recommend"] + ev["auto"] + ev["keep"] > 0) {
      printf "Mod: switch=%d (opus=%d sonnet=%d haiku=%d) revert=%d recommend=%d judge-calls=%d handpick=%d\n", ev["switch"], sw["deep"], sw["balanced"], sw["fast"], ev["revert"], ev["recommend"], ev["judge"], ev["handpick"]
      printf "Mod subagents: cheaper=%d (sonnet=%d haiku=%d) kept-as-set=%d\n", ev["auto"], auto["balanced"], auto["fast"], ev["keep"]
    }
    printf "Model routes: %d", ev["route"]
    if (ev["route"]) printf " (haiku=%d sonnet=%d opus=%d)", route["haiku"], route["sonnet"], route["opus"]
    printf "\n"
    prompts = ev["inject"] + ev["skip"] + ev["trigger"] + ev["mod"]
    changed = ev["route"] + ev["switch"] + ev["auto"]
    if (prompts) printf "Changed share of prompts seen: %.0f%%\n", 100 * changed / prompts
  }
' "${present[@]}"
