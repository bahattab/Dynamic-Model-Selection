# DMS (0 - Dynamic Model Selection) - UserPromptSubmit hook for Claude Code on Windows.
# Reads the hook JSON on stdin and prints a JSON reply that adds routing context.
#   "DMS on"  -> enable automatic routing
#   "DMS off" -> disable automatic routing
#   "DMS ..." -> route this prompt even when automatic routing is off
# State lives in $env:DMS_STATE_DIR or %USERPROFILE%\.config\dms. The prompt text is never echoed.
$ErrorActionPreference = 'SilentlyContinue'

$stateDir = if ($env:DMS_STATE_DIR) { $env:DMS_STATE_DIR } else { Join-Path $HOME '.config\dms' }
$flag = Join-Path $stateDir 'disabled'
$skill = '0-dynamic-model-selection'

$prompt = ''
try {
  $raw = [Console]::In.ReadToEnd()
  if ($raw) { $prompt = [string]((ConvertFrom-Json $raw).prompt) }
} catch { $prompt = '' }

$lower = $prompt.ToLowerInvariant().TrimStart().TrimStart('/')

function Emit([string]$text) {
  $obj = @{ hookSpecificOutput = @{ hookEventName = 'UserPromptSubmit'; additionalContext = $text } }
  [Console]::Out.WriteLine((ConvertTo-Json $obj -Compress -Depth 4))
}

if ($lower -match '^dms off\b') {
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  New-Item -ItemType File -Force -Path $flag | Out-Null
  Emit "DMS: the user turned automatic model routing OFF. Confirm in one line. Prompts that start with DMS are still routed with the $skill skill."
  exit 0
}
if ($lower -match '^dms on\b') {
  Remove-Item -Force -Path $flag
  Emit "DMS: the user turned automatic model routing ON. Confirm in one line; from now on apply the $skill skill (Part B) to every prompt."
  exit 0
}

$triggered = $lower -match '^dms(\b|$)'

if (Test-Path $flag) {
  if ($triggered) {
    Emit "DMS trigger: load the $skill skill and route this task (classify with Part A, route with Part B, report the route). Automatic routing is otherwise OFF."
  }
  exit 0
}

if ($triggered) {
  Emit "DMS trigger: load the $skill skill now and route this task (classify with Part A, route with Part B, report the route)."
} else {
  Emit "DMS automatic model routing is ON. Apply the $skill skill: classify this prompt with Part A, then route it with Part B (answer quick questions directly; run larger work on a subagent or new conversation with the chosen model). Report the route with the skill's format."
}
exit 0
