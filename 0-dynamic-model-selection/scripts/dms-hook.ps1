# DMS (0 - Dynamic Model Selection) - UserPromptSubmit hook for Claude Code on Windows (PowerShell 5.1+ / 7+).
# Reads the hook JSON on stdin and prints one short JSON reply, or nothing.
#
#   "DMS on" / "DMS off"   toggle automatic routing (exact match, optional . or !)
#   "DMS ..." / "/DMS ..." route this prompt on request, even when automatic routing is off
#   other prompts          automatic mode only: short prompts (< DMS_MIN_WORDS words) get nothing;
#                          longer ones get a one-line clear-win reminder
#
# State: $env:DMS_STATE_DIR or %USERPROFILE%\.config\dms, files 'enabled' / 'disabled'; neither = DMS_DEFAULT (on|off, default on).
# Log:   routes.log in the same folder, one line per event, never the prompt text.
# Behaviour is defined by tests/hook-cases.json and must match dms-hook.sh.
$ErrorActionPreference = 'SilentlyContinue'

$stateDir = if ($env:DMS_STATE_DIR) { $env:DMS_STATE_DIR } else { Join-Path $HOME '.config\dms' }
$minWords = 12
if ($env:DMS_MIN_WORDS -match '^\d+$') { $minWords = [int]$env:DMS_MIN_WORDS }
$skill = '0-dynamic-model-selection'

$prompt = ''
try {
  $raw = [Console]::In.ReadToEnd()
  if ($raw) { $prompt = [string]((ConvertFrom-Json $raw).prompt) }
} catch { $prompt = '' }

$lower = $prompt.ToLowerInvariant().Trim()
if ($lower.StartsWith('/')) { $lower = $lower.Substring(1) }

function Write-Log([string]$evt) {
  try {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $line = '{0} {1}' -f ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')), $evt
    Add-Content -Path (Join-Path $stateDir 'routes.log') -Value $line -Encoding ASCII
  } catch { }
}

function Emit([string]$text) {
  $obj = @{ hookSpecificOutput = @{ hookEventName = 'UserPromptSubmit'; additionalContext = $text } }
  [Console]::Out.WriteLine((ConvertTo-Json $obj -Compress -Depth 4))
}

if ($lower -match '^dms off[.!]?$') {
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  Remove-Item -Force -Path (Join-Path $stateDir 'enabled')
  New-Item -ItemType File -Force -Path (Join-Path $stateDir 'disabled') | Out-Null
  Write-Log 'off'
  Emit 'DMS: automatic routing turned OFF. Confirm in one line. DMS <task> still routes on request.'
  exit 0
}
if ($lower -match '^dms on[.!]?$') {
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  Remove-Item -Force -Path (Join-Path $stateDir 'disabled')
  New-Item -ItemType File -Force -Path (Join-Path $stateDir 'enabled') | Out-Null
  Write-Log 'on'
  Emit 'DMS: automatic routing turned ON. Confirm in one line.'
  exit 0
}

if ($lower -match '^dms($|[\s:,.])') {
  Write-Log 'trigger'
  Emit "DMS trigger: load skill $skill, apply its clear-win gate to this task, and route only if it passes."
  exit 0
}

if (Test-Path (Join-Path $stateDir 'disabled')) { $mode = 'off' }
elseif (Test-Path (Join-Path $stateDir 'enabled')) { $mode = 'on' }
elseif ($env:DMS_DEFAULT -and ($env:DMS_DEFAULT.ToLowerInvariant() -in @('off', '0', 'false', 'no'))) { $mode = 'off' }
else { $mode = 'on' }
if ($mode -eq 'off') { exit 0 }

$words = @($prompt -split '\s+' | Where-Object { $_ -ne '' }).Count
if ($words -lt $minWords) {
  Write-Log 'skip'
  exit 0
}

Write-Log 'inject'
Emit "DMS: route only on a clear win (tier differs from your model; task large or opus-grade). Otherwise answer in place, no route line. Rules: skill $skill."
exit 0
