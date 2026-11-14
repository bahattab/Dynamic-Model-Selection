# Summarise the DMS route log for "DMS status" (Windows). Reads only event names, never prompts.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dms-report.ps1 [log-file]
param([string]$LogFile)
$stateDir = if ($env:DMS_STATE_DIR) { $env:DMS_STATE_DIR } else { Join-Path $HOME '.config\dms' }
if (-not $LogFile) { $LogFile = Join-Path $stateDir 'routes.log' }

if (Test-Path (Join-Path $stateDir 'disabled')) { $mode = 'off (DMS off)' }
elseif (Test-Path (Join-Path $stateDir 'enabled')) { $mode = 'on (DMS on)' }
else { $mode = "$(if ($env:DMS_DEFAULT) { $env:DMS_DEFAULT } else { 'on' }) (default)" }
Write-Output "Automatic routing: $mode"

if (-not (Test-Path $LogFile) -or (Get-Item $LogFile).Length -eq 0) {
  Write-Output "Route log: empty ($LogFile)"
  exit 0
}

$ev = @{}; $tier = @{}; $how = @{}; $routes = 0
$lines = @(Get-Content $LogFile | Where-Object { $_.Trim() })
foreach ($line in $lines) {
  $f = $line -split '\s+'
  if ($f.Count -lt 2) { continue }
  if ($f[1] -eq 'route') {
    $routes++
    if ($f.Count -ge 3) { $tier[$f[2]] = 1 + [int]$tier[$f[2]] }
    if ($f.Count -ge 4) { $how[$f[3]] = 1 + [int]$how[$f[3]] }
  } else {
    $ev[$f[1]] = 1 + [int]$ev[$f[1]]
  }
}
Write-Output ("Log: {0} .. {1}" -f ($lines[0] -split '\s+')[0], ($lines[-1] -split '\s+')[0])
Write-Output ("Hook: inject={0} skip={1} trigger={2} on={3} off={4}" -f [int]$ev['inject'], [int]$ev['skip'], [int]$ev['trigger'], [int]$ev['on'], [int]$ev['off'])
$line = "Routes: $routes"
if ($routes) {
  $line += " (haiku={0} sonnet={1} opus={2}; subagent={3} session={4})" -f [int]$tier['haiku'], [int]$tier['sonnet'], [int]$tier['opus'], [int]$how['subagent'], [int]$how['session']
}
Write-Output $line
$prompts = [int]$ev['inject'] + [int]$ev['skip'] + [int]$ev['trigger']
if ($prompts) { Write-Output ("Routed share of prompts seen by the hook: {0:N0}%" -f (100 * $routes / $prompts)) }
