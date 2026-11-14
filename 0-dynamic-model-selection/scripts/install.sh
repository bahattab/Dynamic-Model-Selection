#!/usr/bin/env bash
# Install 0 - Dynamic Model Selection (DMS) for Claude Code and other agents (macOS / Linux).
#
# Usage: bash scripts/install.sh [--no-hook] [--no-agents] [--no-command] [--no-mod] [--keep-conflicts]
#                                [--default-off] [--keep-legacy] [--uninstall]
#
# Installs:
#   ~/.claude/skills/0-dynamic-model-selection/   Claude Code / Claude desktop skill
#   ~/.agents/skills/0-dynamic-model-selection/   shared skills folder for other agents
#   ~/.claude/commands/DMS.md                     /DMS slash command
#   ~/.claude/hooks/dms-hook.sh                   automatic-routing hook
#   ~/.claude/settings.json                       UserPromptSubmit entry (merged, backup kept);
#                                                 --default-off also sets env DMS_DEFAULT=off
#   dms@dynamic-model-selection                   the DMS mod (routing in code), when the claude CLI is
#                                                 on PATH and this folder sits in a clone of the repo;
#                                                 also disables model-selector / model-router mods,
#                                                 which conflict with it (--keep-conflicts to skip)
# Removes the legacy "model-selection" skill and "model-routing.sh" hook from earlier versions
# unless --keep-legacy is given.
set -euo pipefail

NAME="0-dynamic-model-selection"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
AGENTS_DIR="$HOME/.agents"
HOOK_DST="$CLAUDE_DIR/hooks/dms-hook.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

do_hook=1; do_agents=1; do_command=1; do_mod=1; keep_conflicts=0; remove_legacy=1; uninstall=0; default_off=0
for arg in "$@"; do
  case "$arg" in
    --no-hook) do_hook=0 ;;
    --no-agents) do_agents=0 ;;
    --no-command) do_command=0 ;;
    --default-off) default_off=1 ;;
    --no-mod) do_mod=0 ;;
    --keep-conflicts) keep_conflicts=1 ;;
    --keep-legacy) remove_legacy=0 ;;
    --uninstall) uninstall=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "python3 is required to update settings.json" >&2; exit 1; }

# Add (mode=add) or remove (mode=remove) the DMS hook entry in settings.json.
# Also removes legacy entries that call model-routing.sh. Writes a backup first.
update_settings() {
  local mode="$1"
  mkdir -p "$CLAUDE_DIR"
  [ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak-dms"
  python3 - "$SETTINGS" "$HOOK_DST" "$mode" "$default_off" <<'PY'
import json, os, sys
path, hook, mode, default_off = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
hooks = data.setdefault("hooks", {})
groups = hooks.get("UserPromptSubmit", [])
def ours(h):
    cmd = h.get("command", "")
    return "dms-hook" in cmd or "model-routing.sh" in cmd
kept = []
for g in groups:
    inner = [h for h in g.get("hooks", []) if not ours(h)]
    if inner:
        g["hooks"] = inner
        kept.append(g)
if mode == "add":
    kept.append({"hooks": [{"type": "command",
                            "command": f'"{hook}"',
                            "timeout": 10}]})
if kept:
    hooks["UserPromptSubmit"] = kept
else:
    hooks.pop("UserPromptSubmit", None)
if not hooks:
    data.pop("hooks", None)
env = data.get("env", {})
if mode == "add" and default_off:
    env["DMS_DEFAULT"] = "off"
else:
    env.pop("DMS_DEFAULT", None)
if env:
    data["env"] = env
else:
    data.pop("env", None)
tmp = path + ".tmp-dms"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
}

remove_legacy_files() {
  local legacy="$CLAUDE_DIR/skills/model-selection"
  if [ -f "$legacy/SKILL.md" ] && grep -q "^name: model-selection" "$legacy/SKILL.md"; then
    rm -rf "$legacy" && echo "Removed legacy skill: $legacy"
  fi
  if [ -f "$CLAUDE_DIR/hooks/model-routing.sh" ]; then
    rm -f "$CLAUDE_DIR/hooks/model-routing.sh" && echo "Removed legacy hook: $CLAUDE_DIR/hooks/model-routing.sh"
  fi
}

copy_skill() {
  local dst="$1/$NAME"
  mkdir -p "$1"
  if [ "$(cd "$SRC" && pwd -P)" = "$(mkdir -p "$dst" && cd "$dst" && pwd -P)" ]; then
    echo "Skill already in place: $dst"; return
  fi
  rm -rf "$dst"
  cp -R "$SRC" "$dst"
  rm -rf "$dst/.git"
  chmod +x "$dst"/scripts/*.sh 2>/dev/null || true
  echo "Installed skill: $dst"
}

# Mods that would fight DMS over the same model decision (see README "Other routing mods").
CONFLICTS="model-selector model-router"
MARKET_ROOT="$(cd "$SRC/.." && pwd)"

DMS_STATE="${DMS_STATE_DIR:-$HOME/.config/dms}"
CONFLICT_RECORD="$DMS_STATE/disabled-conflicts"

# Plugin ids (name@marketplace) of a plugin in `claude plugin list` output, whatever the bullet.
plugin_ids() {
  printf '%s\n' "$2" | grep -oE "(^|[^A-Za-z0-9._-])$1@[A-Za-z0-9._-]+" | sed -E 's/^[^A-Za-z0-9._-]//' | sort -u || true
}

install_mod() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "Skipped the DMS mod: the claude CLI is not on PATH (the hook + skill still work)."; return 0
  fi
  if [ ! -f "$MARKET_ROOT/.claude-plugin/marketplace.json" ] || [ ! -d "$MARKET_ROOT/plugins/dms" ]; then
    echo "Skipped the DMS mod: run the installer from a clone of the repository to get it."; return 0
  fi
  claude plugin marketplace add "$MARKET_ROOT" >/dev/null 2>&1 || true
  if claude plugin install dms@dynamic-model-selection >/dev/null 2>&1; then
    echo "Installed mod: dms@dynamic-model-selection"
  else
    # Without the DMS mod running, the other routing mods stay as they are.
    echo "DMS mod install FAILED (the hook + skill still work; other routing mods left on)" >&2
    return 0
  fi
  [ "$keep_conflicts" -eq 1 ] && return 0
  local listed name id
  listed="$(claude plugin list 2>/dev/null || true)"
  for name in $CONFLICTS; do
    for id in $(plugin_ids "$name" "$listed"); do
      if claude plugin disable "$id" >/dev/null 2>&1; then
        echo "Disabled conflicting mod: $id (turned back on by --uninstall)"
        mkdir -p "$DMS_STATE" && printf '%s\n' "$id" >> "$CONFLICT_RECORD"
      fi
    done
  done
  return 0
}

uninstall_mod() {
  command -v claude >/dev/null 2>&1 || return 0
  if claude plugin uninstall dms@dynamic-model-selection >/dev/null 2>&1; then echo "Removed mod: dms@dynamic-model-selection"; fi
  if [ -f "$CONFLICT_RECORD" ]; then
    local id
    while read -r id; do
      [ -n "$id" ] || continue
      if claude plugin enable "$id" >/dev/null 2>&1; then echo "Re-enabled mod: $id"; fi
    done < <(sort -u "$CONFLICT_RECORD")
    rm -f "$CONFLICT_RECORD"
  fi
  return 0
}

if [ "$uninstall" -eq 1 ]; then
  rm -rf "$CLAUDE_DIR/skills/$NAME" "$AGENTS_DIR/skills/$NAME" "$CLAUDE_DIR/commands/DMS.md" "$HOOK_DST"
  [ -f "$SETTINGS" ] && update_settings remove
  uninstall_mod
  echo "DMS uninstalled. Settings backup: $SETTINGS.bak-dms"
  exit 0
fi

copy_skill "$CLAUDE_DIR/skills"
[ "$do_agents" -eq 1 ] && copy_skill "$AGENTS_DIR/skills"

if [ "$do_command" -eq 1 ]; then
  mkdir -p "$CLAUDE_DIR/commands"
  cp "$SRC/commands/DMS.md" "$CLAUDE_DIR/commands/DMS.md"
  echo "Installed command: $CLAUDE_DIR/commands/DMS.md"
fi

[ "$remove_legacy" -eq 1 ] && remove_legacy_files

if [ "$do_hook" -eq 1 ]; then
  mkdir -p "$CLAUDE_DIR/hooks"
  cp "$SRC/scripts/dms-hook.sh" "$HOOK_DST"
  chmod +x "$HOOK_DST"
  update_settings add
  echo "Installed hook: $HOOK_DST (UserPromptSubmit in $SETTINGS)"
else
  [ -f "$SETTINGS" ] && update_settings remove
fi

[ "$do_mod" -eq 1 ] && install_mod

echo "Done. Version $(cat "$SRC/VERSION" 2>/dev/null || echo unknown)."
echo "Start a new session (or open /hooks once) so Claude Code loads the skill and hook."
