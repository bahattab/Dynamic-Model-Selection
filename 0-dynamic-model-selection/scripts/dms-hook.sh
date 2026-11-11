#!/usr/bin/env bash
# DMS (0 - Dynamic Model Selection) — UserPromptSubmit hook for Claude Code.
# Reads the hook JSON on stdin and prints a JSON reply that adds routing context.
#   "DMS on"  -> enable automatic routing
#   "DMS off" -> disable automatic routing
#   "DMS ..." -> route this prompt even when automatic routing is off
# State lives in ${DMS_STATE_DIR:-$HOME/.config/dms}. The user's prompt text is
# never copied into the output.
set -u

STATE_DIR="${DMS_STATE_DIR:-$HOME/.config/dms}"
FLAG="$STATE_DIR/disabled"
SKILL="0-dynamic-model-selection"

input="$(cat 2>/dev/null || true)"
prompt=""
if command -v jq >/dev/null 2>&1; then
  prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  prompt="$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("prompt",""))
except Exception: pass' 2>/dev/null || true)"
fi

# Lowercase, trim leading whitespace and a leading slash.
lower="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's#^/##')"

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$1"
}

case "$lower" in
  "dms off"|"dms off "*|"dms off."*)
    mkdir -p "$STATE_DIR" && : > "$FLAG"
    emit "DMS: the user turned automatic model routing OFF. Confirm in one line. Prompts that start with DMS are still routed with the $SKILL skill."
    exit 0 ;;
  "dms on"|"dms on "*|"dms on."*)
    rm -f "$FLAG"
    emit "DMS: the user turned automatic model routing ON. Confirm in one line; from now on apply the $SKILL skill (Part B) to every prompt."
    exit 0 ;;
esac

triggered=0
case "$lower" in
  dms|"dms "*|dms:*|"dms,"*|"dms."*) triggered=1 ;;
esac

if [ -f "$FLAG" ]; then
  if [ "$triggered" -eq 1 ]; then
    emit "DMS trigger: load the $SKILL skill and route this task (classify with Part A, route with Part B, report the route). Automatic routing is otherwise OFF."
  fi
  exit 0
fi

if [ "$triggered" -eq 1 ]; then
  emit "DMS trigger: load the $SKILL skill now and route this task (classify with Part A, route with Part B, report the route)."
else
  emit "DMS automatic model routing is ON. Apply the $SKILL skill: classify this prompt with Part A, then route it with Part B (answer quick questions directly; run larger work on a subagent or new conversation with the chosen model). Report the route with the skill's format."
fi
exit 0
