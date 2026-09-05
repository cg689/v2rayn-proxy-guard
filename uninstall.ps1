<#
.SYNOPSIS
    Removes the v2rayN Proxy Guard scheduled task.
#>
$ErrorActionPreference = 'Stop'
$taskName = 'v2rayN ProxyGuard'
schtasks /delete /tn $taskName /f | Out-Null
if ($LASTEXITCODE -ne 0) { throw "schtasks failed with exit code $LASTEXITCODE (task not found?)" }
Write-Host "OK: scheduled task '$taskName' removed. The script file itself was not deleted."
