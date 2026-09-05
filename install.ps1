<#
.SYNOPSIS
    Registers the v2rayN Proxy Guard as a Windows scheduled task.

    The task launches PowerShell through run-hidden.vbs (wscript.exe host),
    which has no console window - otherwise a blue console flash would pop
    up on every trigger.

.PARAMETER IntervalMinutes
    How often the guard runs, in minutes. Default: 5.

.PARAMETER Port
    Force a fixed v2rayN port instead of auto-detection. Default: auto.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -IntervalMinutes 1 -Port 10809
#>
param(
    [int]$IntervalMinutes = 5,
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'proxy-guard.ps1'
$vbsPath    = Join-Path $PSScriptRoot 'run-hidden.vbs'
if (-not (Test-Path $scriptPath)) { throw "proxy-guard.ps1 not found next to install.ps1 ($PSScriptRoot)" }
if (-not (Test-Path $vbsPath))    { throw "run-hidden.vbs not found next to install.ps1 ($PSScriptRoot)" }

$taskName = 'v2rayN ProxyGuard'
# wscript.exe run-hidden.vbs "<script>" [-Port N] -Once
$taskArgs = "`"$vbsPath`" `"$scriptPath`""
if ($Port -gt 0) { $taskArgs += " -Port $Port" }
$taskArgs += ' -Once'

schtasks /create /tn $taskName /sc minute /mo $IntervalMinutes `
    /tr "wscript.exe $taskArgs" /f | Out-Null
if ($LASTEXITCODE -ne 0) { throw "schtasks failed with exit code $LASTEXITCODE" }

Write-Host "OK: scheduled task '$taskName' created (every $IntervalMinutes minute(s))."
Write-Host "Port mode: $(if ($Port -gt 0) { "fixed port $Port" } else { 'auto-detect from v2rayN config' })"
Write-Host "Log file : $env:USERPROFILE\v2rayn-proxy-guard.log"
Write-Host "Remove   : .\uninstall.ps1  (or schtasks /delete /tn `"$taskName`" /f)"

# run one check right away so the user sees it working
if ($Port -gt 0) {
    & $scriptPath -Once -Port $Port
} else {
    & $scriptPath -Once
}

# and verify the scheduled task itself can start (runs hidden, no flash)
schtasks /run /tn $taskName | Out-Null
if ($LASTEXITCODE -ne 0) { throw "schtasks /run failed with exit code $LASTEXITCODE" }
Write-Host "Task self-test: triggered '$taskName' once via the Task Scheduler."
