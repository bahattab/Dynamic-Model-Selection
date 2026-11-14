<#
.SYNOPSIS
  Install 0 - Dynamic Model Selection (DMS) for Claude Code / Claude desktop and other agents on Windows.

.DESCRIPTION
  Installs:
    %USERPROFILE%\.claude\skills\0-dynamic-model-selection\   Claude Code / Claude desktop skill
    %USERPROFILE%\.agents\skills\0-dynamic-model-selection\   shared skills folder for other agents
    %USERPROFILE%\.claude\commands\DMS.md                     /DMS slash command
    %USERPROFILE%\.claude\hooks\dms-hook.ps1                  automatic-routing hook
    %USERPROFILE%\.claude\settings.json                       UserPromptSubmit entry (merged, backup kept);
                                                              -DefaultOff also sets env DMS_DEFAULT=off
  Removes the legacy "model-selection" skill and "model-routing.sh" hook unless -KeepLegacy is given.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Uninstall
#>
param(
  [switch]$NoHook,
  [switch]$NoAgents,
  [switch]$NoCommand,
  [switch]$DefaultOff,
  [switch]$KeepLegacy,
  [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'

$Name      = '0-dynamic-model-selection'
$Src       = Split-Path -Parent $PSScriptRoot
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$AgentsDir = Join-Path $HOME '.agents'
$HookDst   = Join-Path $ClaudeDir 'hooks\dms-hook.ps1'
$Settings  = Join-Path $ClaudeDir 'settings.json'

function Update-Settings([string]$Mode) {
  New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
  $data = [pscustomobject]@{}
  if ((Test-Path $Settings) -and ((Get-Item $Settings).Length -gt 0)) {
    Copy-Item $Settings "$Settings.bak-dms" -Force
    $data = Get-Content $Settings -Raw -Encoding UTF8 | ConvertFrom-Json
  }
  if (-not $data.PSObject.Properties['hooks']) { $data | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force }
  $groups = @()
  if ($data.hooks.PSObject.Properties['UserPromptSubmit']) { $groups = @($data.hooks.UserPromptSubmit) }
  $kept = @()
  foreach ($g in $groups) {
    $inner = @($g.hooks | Where-Object { $_.command -notmatch 'dms-hook|model-routing\.sh' })
    if ($inner.Count -gt 0) { $g.hooks = $inner; $kept += $g }
  }
  if ($Mode -eq 'add') {
    # Works whether Claude Code runs hooks through PowerShell or Git Bash.
    $kept += [pscustomobject]@{
      hooks = @([pscustomobject]@{
        type    = 'command'
        command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$HookDst`""
        timeout = 10
      })
    }
  }
  if ($kept.Count -gt 0) {
    $data.hooks | Add-Member -NotePropertyName UserPromptSubmit -NotePropertyValue ([object[]]$kept) -Force
  } elseif ($data.hooks.PSObject.Properties['UserPromptSubmit']) {
    $data.hooks.PSObject.Properties.Remove('UserPromptSubmit')
  }
  if (@($data.hooks.PSObject.Properties).Count -eq 0) { $data.PSObject.Properties.Remove('hooks') }

  if (-not $data.PSObject.Properties['env']) { $data | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) -Force }
  if ($Mode -eq 'add' -and $DefaultOff) {
    $data.env | Add-Member -NotePropertyName DMS_DEFAULT -NotePropertyValue 'off' -Force
  } elseif ($data.env.PSObject.Properties['DMS_DEFAULT']) {
    $data.env.PSObject.Properties.Remove('DMS_DEFAULT')
  }
  if (@($data.env.PSObject.Properties).Count -eq 0) { $data.PSObject.Properties.Remove('env') }

  # Write to a temporary file first, then swap it in, so a failure never leaves a half-written settings.json.
  $json = ConvertTo-Json $data -Depth 20
  $tmp = "$Settings.tmp-dms"
  [System.IO.File]::WriteAllText($tmp, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
  if (Test-Path $Settings) { [System.IO.File]::Replace($tmp, $Settings, $null) } else { Move-Item -Force $tmp $Settings }
}

function Copy-Skill([string]$Root) {
  $dst = Join-Path $Root $Name
  New-Item -ItemType Directory -Force -Path $Root | Out-Null
  if ((Resolve-Path $Src).Path -eq (Join-Path (Resolve-Path $Root).Path $Name)) {
    Write-Host "Skill already in place: $dst"; return
  }
  if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
  Copy-Item -Recurse -Force $Src $dst
  if (Test-Path (Join-Path $dst '.git')) { Remove-Item -Recurse -Force (Join-Path $dst '.git') }
  Write-Host "Installed skill: $dst"
}

if ($Uninstall) {
  foreach ($p in @((Join-Path $ClaudeDir "skills\$Name"), (Join-Path $AgentsDir "skills\$Name"),
                   (Join-Path $ClaudeDir 'commands\DMS.md'), $HookDst)) {
    if (Test-Path $p) { Remove-Item -Recurse -Force $p }
  }
  if (Test-Path $Settings) { Update-Settings 'remove' }
  Write-Host "DMS uninstalled. Settings backup: $Settings.bak-dms"
  exit 0
}

Copy-Skill (Join-Path $ClaudeDir 'skills')
if (-not $NoAgents) { Copy-Skill (Join-Path $AgentsDir 'skills') }

if (-not $NoCommand) {
  New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeDir 'commands') | Out-Null
  Copy-Item -Force (Join-Path $Src 'commands\DMS.md') (Join-Path $ClaudeDir 'commands\DMS.md')
  Write-Host "Installed command: $(Join-Path $ClaudeDir 'commands\DMS.md')"
}

if (-not $KeepLegacy) {
  $legacy = Join-Path $ClaudeDir 'skills\model-selection'
  if ((Test-Path (Join-Path $legacy 'SKILL.md')) -and (Select-String -Quiet -Path (Join-Path $legacy 'SKILL.md') -Pattern '^name: model-selection')) {
    Remove-Item -Recurse -Force $legacy; Write-Host "Removed legacy skill: $legacy"
  }
  $legacyHook = Join-Path $ClaudeDir 'hooks\model-routing.sh'
  if (Test-Path $legacyHook) { Remove-Item -Force $legacyHook; Write-Host "Removed legacy hook: $legacyHook" }
}

if (-not $NoHook) {
  New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeDir 'hooks') | Out-Null
  Copy-Item -Force (Join-Path $Src 'scripts\dms-hook.ps1') $HookDst
  Update-Settings 'add'
  Write-Host "Installed hook: $HookDst (UserPromptSubmit in $Settings)"
} elseif (Test-Path $Settings) {
  Update-Settings 'remove'
}

$ver = if (Test-Path (Join-Path $Src 'VERSION')) { (Get-Content (Join-Path $Src 'VERSION') -Raw).Trim() } else { 'unknown' }
Write-Host "Done. Version $ver."
Write-Host "Start a new session (or open /hooks once) so Claude Code loads the skill and hook."
