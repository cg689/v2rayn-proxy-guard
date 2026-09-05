<#
.SYNOPSIS
    v2rayN Proxy Guard - automatically reclaim the Windows system proxy for v2rayN.

.DESCRIPTION
    Detects the local inbound port of the installed v2rayN automatically
    (from guiNConfig.json, falling back to the generated core config),
    then restores the Windows system proxy to "127.0.0.1:<port>" whenever
    another program (e.g. another proxy client) overwrites or disables it.

    The guard ONLY acts while v2rayN.exe is running AND v2rayN's own system
    proxy mode is "set proxy" (SysProxyType = ForcedChange). If v2rayN is
    closed, or the user chose "clear / do not touch system proxy" inside
    v2rayN, the script does nothing - your intent is respected.

.PARAMETER Port
    Force a fixed port instead of auto-detection. The guard still requires
    v2rayN.exe to be running before it acts.

.PARAMETER Once
    Run one check and exit (used by the scheduled task).

.PARAMETER IntervalMinutes
    In watch mode: minutes between checks. Default 5 minutes.

.PARAMETER LogPath
    Path of the fix log. Default: <profile>\v2rayn-proxy-guard.log

.EXAMPLE
    .\proxy-guard.ps1 -Once                 # single check
    .\proxy-guard.ps1                       # watch mode, check every 5 min
    .\proxy-guard.ps1 -Port 10809 -Once     # force a port

.NOTES
    Works on Windows PowerShell 5.1 and 7+. No admin rights required
    (writes only to HKCU).
#>

[CmdletBinding()]
param(
    [int]$Port = 0,
    [switch]$Once,
    [int]$IntervalMinutes = 5,
    [string]$LogPath = "$env:USERPROFILE\v2rayn-proxy-guard.log"
)

$script:ValidProxyServers = @()
$script:MainPort = 0

function Write-GuardLog {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    try {
        # keep the log under ~512 KB
        if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt 512KB) {
            Clear-Content $LogPath
        }
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    } catch { }
}

function Find-V2rayNDir {
    # 1) the running process tells us exactly where v2rayN lives
    $proc = Get-Process v2rayN -ErrorAction SilentlyContinue |
            Where-Object { $_.Path } | Select-Object -First 1
    if ($proc) {
        return Split-Path $proc.Path -Parent
    }

    # 2) the auto-run scheduled task created by v2rayN ("v2rayNAutoRun_*")
    $task = Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -like 'v2rayNAutoRun_*' } |
            Select-Object -First 1
    if ($task -and $task.Actions.Count -gt 0) {
        $exe = $task.Actions[0].Execute.Trim('"')
        if (Test-Path $exe) { return Split-Path $exe -Parent }
    }

    # 3) common locations
    $candidates = @(
        "$env:ProgramFiles\v2rayN",
        "${env:ProgramFiles(x86)}\v2rayN",
        "$env:LOCALAPPDATA\Programs\v2rayN",
        "$env:USERPROFILE\Desktop\v2rayN",
        "D:\Software\v2rayN-windows-64-desktop\v2rayN-windows-64",
        "D:\v2rayN",
        "C:\v2rayN"
    )
    foreach ($dir in $candidates) {
        if (Test-Path (Join-Path $dir 'v2rayN.exe')) { return $dir }
    }
    return $null
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { $null }
}

function Get-V2rayNPorts {
    # returns $null when the port cannot be determined
    param([string]$V2rayNDir)

    # --- primary source: guiNConfig.json -> Inbound[].LocalPort -----------
    $gui = Read-JsonFile (Join-Path $V2rayNDir 'guiConfigs\guiNConfig.json')
    if ($gui -and $gui.Inbound -and $gui.Inbound.Count -gt 0) {
        $main  = [int]$gui.Inbound[0].LocalPort
        $ports = @($main)
        if ($gui.Inbound[0].SecondLocalPortEnabled) {
            $ports += ($main + 1)   # second inbound is always main + 1
        }
        return @{
            Ports         = $ports
            MainPort      = $main
            SysProxyType  = if ($gui.SystemProxyItem) { [int]$gui.SystemProxyItem.SysProxyType } else { $null }
        }
    }

    # --- fallback: the generated core config (binConfigs\config.json) -----
    # NOTE: on this path the GUI config was unreadable, so SysProxyType is
    # unknown ($null) and the guard proceeds. If the user actually chose
    # "clear / unchanged" in v2rayN AND guiNConfig.json is corrupt, the
    # guard may act against that intent - accepted trade-off, because a
    # broken guiNConfig.json is far rarer than a hijacked system proxy.
    # sing-box format:  inbounds[].listen_port / type = mixed|socks|http
    # xray format:      inbounds[].port       / protocol = socks|http
    $core = Read-JsonFile (Join-Path $V2rayNDir 'binConfigs\config.json')
    if ($core -and $core.inbounds) {
        $ports = @()
        foreach ($in in $core.inbounds) {
            $type = if ($in.type) { $in.type } else { $in.protocol }
            if ($type -in @('mixed', 'socks', 'http')) {
                $p = if ($in.listen_port) { [int]$in.listen_port } elseif ($in.port) { [int]$in.port } else { 0 }
                if ($p -gt 0) { $ports += $p }
            }
        }
        if ($ports.Count -gt 0) {
            $ports = $ports | Sort-Object -Unique
            return @{
                Ports        = $ports
                MainPort     = $ports[0]
                SysProxyType = $null
            }
        }
    }
    return $null
}

function Test-ProxyMatches {
    # the proxy value is valid if it points at any of v2rayN's own ports
    param([string]$ProxyServer)
    foreach ($p in $script:ValidProxyServers) {
        if ($ProxyServer -eq $p) { return $true }
    }
    return $false
}

function Set-SystemProxy {
    # writes and VERIFIES; returns $true only when the registry really
    # holds the expected values afterwards
    param([string]$Target)
    $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    try {
        Set-ItemProperty $reg -Name ProxyEnable -Value 1 -Type DWord -ErrorAction Stop
        Set-ItemProperty $reg -Name ProxyServer -Value $Target -Type String -ErrorAction Stop
    } catch {
        Write-GuardLog "ERROR: registry write failed: $($_.Exception.Message)"
        return $false
    }
    $check = Get-ItemProperty $reg
    return ([int]$check.ProxyEnable -eq 1 -and [string]$check.ProxyServer -eq $Target)
}

function Invoke-GuardCheck {
    # ---- precondition 1: v2rayN must be running -----------------------------
    $proc = Get-Process v2rayN -ErrorAction SilentlyContinue
    if (-not $proc) { return }   # v2rayN closed -> user probably wants direct access

    # ---- determine the port to guard ---------------------------------------
    if ($Port -gt 0) {
        # explicit -Port: trust the user, skip installation detection
        $script:MainPort = $Port
        $script:ValidProxyServers = @("127.0.0.1:$Port", "localhost:$Port")
    } else {
        $dir = Find-V2rayNDir
        if (-not $dir) { return }

        $info = Get-V2rayNPorts -V2rayNDir $dir
        if (-not $info) {
            Write-GuardLog "WARN: v2rayN found at '$dir' but no inbound port could be detected."
            return
        }
        if ($info.SysProxyType -ne $null -and $info.SysProxyType -ne 1) {
            # 0 = forced clear, 2 = unchanged, 3 = PAC -> user did not ask for a
            # fixed system proxy, so we must not fight other settings
            return
        }
        $script:MainPort = $info.MainPort
        $script:ValidProxyServers = @()
        foreach ($p in $info.Ports) {
            $script:ValidProxyServers += "127.0.0.1:$p"
            $script:ValidProxyServers += "localhost:$p"
        }
    }

    # ---- check & fix --------------------------------------------------------
    $reg    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $props  = Get-ItemProperty $reg
    $enable = [int]$props.ProxyEnable
    $server = [string]$props.ProxyServer

    if ($enable -eq 1 -and (Test-ProxyMatches -ProxyServer $server)) { return }   # all good

    $target = "127.0.0.1:$($script:MainPort)"
    if (Set-SystemProxy -Target $target) {
        Write-GuardLog "FIXED: proxy was enable=$enable server='$server' -> restored to '$target'"
    } else {
        Write-GuardLog "ERROR: could not restore proxy (wanted enable=1 server='$target', had enable=$enable server='$server')"
    }
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------
if ($Once) {
    Invoke-GuardCheck
    exit 0
}

Write-Host "v2rayN Proxy Guard started. Checking every $IntervalMinutes minute(s). Ctrl+C to stop."
Write-GuardLog "guard started: interval=${IntervalMinutes}min, port mode=$(if ($Port -gt 0) { "fixed $Port" } else { 'auto' }), log=$LogPath"
while ($true) {
    Invoke-GuardCheck
    Start-Sleep -Seconds (60 * $IntervalMinutes)
}
