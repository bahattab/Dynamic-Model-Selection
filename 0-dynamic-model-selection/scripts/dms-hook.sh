#!/usr/bin/env bash
# DMS (0 - Dynamic Model Selection) — UserPromptSubmit hook for Claude Code (bash).
# Reads the hook JSON on stdin and prints one short JSON reply, or nothing.
#
#   "DMS on" / "DMS off"   toggle automatic routing (exact match, optional . or !)
#   "DMS ..." / "/DMS ..." route this prompt on request, even when automatic routing is off
#   other prompts          automatic mode only: short prompts (< DMS_MIN_WORDS words) get nothing;
#                          longer ones get a one-line clear-win reminder
#
# State: ${DMS_STATE_DIR:-$HOME/.config/dms}/enabled or /disabled; neither = DMS_DEFAULT (on|off, default on).
# Log:   routes.log in the same folder, one line per event, never the prompt text.
# Behaviour is defined by tests/hook-cases.json and must match dms-hook.ps1.
set -u

STATE_DIR="${DMS_STATE_DIR:-$HOME/.config/dms}"
MIN_WORDS="${DMS_MIN_WORDS:-12}"
case "$MIN_WORDS" in ''|*[!0-9]*) MIN_WORDS=12 ;; esac
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

# Lowercase, trim surrounding whitespace, drop one leading slash.
lower="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
lower="${lower#"${lower%%[![:space:]]*}"}"
lower="${lower%"${lower##*[![:space:]]}"}"
lower="${lower#/}"

log() {
  mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >> "$STATE_DIR/routes.log" 2>/dev/null
  return 0
}

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$1"
}

case "$lower" in
  "dms off"|"dms off."|"dms off!")
    mkdir -p "$STATE_DIR" && rm -f "$STATE_DIR/enabled" && : > "$STATE_DIR/disabled"
    log off
    emit "DMS: automatic routing turned OFF. Confirm in one line. DMS <task> still routes on request."
    exit 0 ;;
  "dms on"|"dms on."|"dms on!")
    mkdir -p "$STATE_DIR" && rm -f "$STATE_DIR/disabled" && : > "$STATE_DIR/enabled"
    log on
    emit "DMS: automatic routing turned ON. Confirm in one line."
    exit 0 ;;
esac

case "$lower" in
  dms|"dms "*|"dms	"*|dms:*|dms,*|dms.*)
    log trigger
    emit "DMS trigger: load skill $SKILL, apply its clear-win gate to this task, and route only if it passes."
    exit 0 ;;
esac

if [ -f "$STATE_DIR/disabled" ]; then
  mode=off
elif [ -f "$STATE_DIR/enabled" ]; then
  mode=on
else
  case "$(printf '%s' "${DMS_DEFAULT:-on}" | tr '[:upper:]' '[:lower:]')" in
    off|0|false|no) mode=off ;;
    *) mode=on ;;
  esac
fi
[ "$mode" = off ] && exit 0

words="$(printf '%s' "$prompt" | wc -w | tr -d '[:space:]')"
if [ "${words:-0}" -lt "$MIN_WORDS" ]; then
  log skip
  exit 0
fi

log inject
emit "DMS: route only on a clear win (tier differs from your model; task large or opus-grade). Otherwise answer in place, no route line. Rules: skill $SKILL."
exit 0
