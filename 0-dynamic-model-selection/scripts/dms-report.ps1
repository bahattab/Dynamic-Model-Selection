# Summarise the DMS route log for "DMS status" (Windows). Reads only event names, never prompts.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dms-report.ps1 [log-file]
# Events: see dms-report.sh.
param([string]$LogFile)
$stateDir = if ($env:DMS_STATE_DIR) { $env:DMS_STATE_DIR } else { Join-Path $HOME '.config\dms' }
if (-not $LogFile) { $LogFile = Join-Path $stateDir 'routes.log' }

if (Test-Path (Join-Path $stateDir 'disabled')) { $mode = 'off (DMS off)' }
elseif (Test-Path (Join-Path $stateDir 'enabled')) { $mode = 'on (DMS on)' }
else { $mode = "$(if ($env:DMS_DEFAULT) { $env:DMS_DEFAULT } else { 'on' }) (default)" }
Write-Output "Automatic routing: $mode"
$modActive = Join-Path $stateDir 'mod-active'
if ((Test-Path $modActive) -and ((Get-Item $modActive).LastWriteTime -gt (Get-Date).AddMinutes(-30))) {
  Write-Output 'Engine: DMS mod (routing in code)'
} else {
  Write-Output 'Engine: hook + skill'
}

if (-not (Test-Path $LogFile) -or (Get-Item $LogFile).Length -eq 0) {
  Write-Output "Route log: empty ($LogFile)"
  exit 0
}

$ev = @{}; $route = @{}; $sw = @{}; $auto = @{}
$lines = @(Get-Content $LogFile | Where-Object { $_.Trim() })
foreach ($line in $lines) {
  $f = $line -split '\s+'
  if ($f.Count -lt 2) { continue }
  $ev[$f[1]] = 1 + [int]$ev[$f[1]]
  if ($f.Count -ge 3) {
    switch ($f[1]) {
      'route'  { $route[$f[2]] = 1 + [int]$route[$f[2]] }
      'switch' { $sw[$f[2]] = 1 + [int]$sw[$f[2]] }
      'auto'   { $auto[$f[2]] = 1 + [int]$auto[$f[2]] }
    }
  }
}
function N([hashtable]$t, [string]$k) { [int]$t[$k] }
Write-Output ("Log: {0} .. {1}" -f ($lines[0] -split '\s+')[0], ($lines[-1] -split '\s+')[0])
Write-Output ("Hook: inject={0} skip={1} trigger={2} mod={3} on={4} off={5}" -f (N $ev 'inject'), (N $ev 'skip'), (N $ev 'trigger'), (N $ev 'mod'), (N $ev 'on'), (N $ev 'off'))
if (((N $ev 'mod') + (N $ev 'pass') + (N $ev 'switch') + (N $ev 'recommend') + (N $ev 'auto') + (N $ev 'keep')) -gt 0) {
  Write-Output ("Mod: switch={0} (opus={1} sonnet={2} haiku={3}) recommend={4} judge-calls={5} handpick={6}" -f (N $ev 'switch'), (N $sw 'deep'), (N $sw 'balanced'), (N $sw 'fast'), (N $ev 'recommend'), (N $ev 'judge'), (N $ev 'handpick'))
  Write-Output ("Mod subagents: cheaper={0} (sonnet={1} haiku={2}) kept-as-set={3}" -f (N $ev 'auto'), (N $auto 'balanced'), (N $auto 'fast'), (N $ev 'keep'))
}
$line = "Model routes: $(N $ev 'route')"
if ((N $ev 'route') -gt 0) { $line += " (haiku={0} sonnet={1} opus={2})" -f (N $route 'haiku'), (N $route 'sonnet'), (N $route 'opus') }
Write-Output $line
$prompts = (N $ev 'inject') + (N $ev 'skip') + (N $ev 'trigger') + (N $ev 'mod')
$changed = (N $ev 'route') + (N $ev 'switch') + (N $ev 'auto')
if ($prompts) { Write-Output ("Changed share of prompts seen: {0:N0}%" -f (100 * $changed / $prompts)) }
