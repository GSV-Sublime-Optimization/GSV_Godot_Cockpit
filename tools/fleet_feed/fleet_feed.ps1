# fleet_feed.ps1 - read-only fleet telemetry probe (KiloCore fleet).
#
# Writes ONE typed JSON snapshot for the holographic cockpit to read:
#   C:\GSV\state\fleet-telemetry.json
# Schema: kilocore.fleet-telemetry.v1 (see tools/fleet_feed/README.md).
#
# The cockpit itself runs NO shell and holds NO credentials. This script runs
# on the rig (via mssh or the MuseFleetFeed scheduled task, every 5 min) and
# the cockpit reads the snapshot file with caps + schema checks + age - the
# same pattern as Mind View's mind_feed.py. Honest states only: a rig or
# service with no live source is recorded unavailable/unknown, never faked.
#
# Rules baked in:
# - READ-ONLY everywhere: CIM reads, HTTP GETs, TCP connects, scheduled-task
#   state reads, SSH remote reads (echo / memory / process list). No writes
#   to any fleet machine except this snapshot file on the MSI itself.
# - Xanadu: HTTP ONLY (Icecast status-json). NEVER SSH to Xanadu - the pause
#   stands until Keath lifts it. There is no xanadu SSH call in this script.
# - i3: LAN alias `i3` first, tailscale alias `i3-tailscale` second; each SSH
#   attempt is hard-capped (8 s) via Start-Process + WaitForExit + Kill, so a
#   hanging session-0 SSH can never stall the feed.
# - L9: LAN alias `kilodesktop` via Git's bundled ssh.exe (MSI Windows
#   OpenSSH returns exit 255); hard-capped the same way.
# - Every remote check has a timeout; every failure records a reason string.
#
# PowerShell 5.1, ASCII only. Run: powershell -NoProfile -ExecutionPolicy
# Bypass -File C:\GSV\tools\fleet-feed\fleet_feed.ps1

$ErrorActionPreference = "Stop"

# GSV_FLEET_TELEMETRY_PATH moves the snapshot (the cockpit readers honour the same variable).
$SnapshotPath = "C:\GSV\state\fleet-telemetry.json"
if ($env:GSV_FLEET_TELEMETRY_PATH) { $SnapshotPath = $env:GSV_FLEET_TELEMETRY_PATH }
$GitSsh = "C:\Program Files\Git\usr\bin\ssh.exe"
$SshTimeoutMs = 8000

function Test-TcpPort($HostName, $Port, $TimeoutMs) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return "timeout"
        }
        $client.EndConnect($ar) | Out-Null
        return "open"
    } catch {
        return "closed"
    } finally {
        $client.Close()
    }
}

function Get-HttpStatus($Url, $TimeoutSec) {
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        return @{ status = [int]$r.StatusCode; ok = $true; error = "" }
    } catch {
        $code = $null
        if ($_.Exception.Response -ne $null) {
            $code = [int]$_.Exception.Response.StatusCode
        }
        return @{ status = $code; ok = $false; error = "http_error" }
    }
}

function Invoke-SshProbe($SshExe, $Alias, $RemoteCommand, $TimeoutMs) {
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $argList = $Alias + " " + $RemoteCommand
        $p = Start-Process -FilePath $SshExe -ArgumentList $argList `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
            -NoNewWindow -PassThru -ErrorAction Stop
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch {}
            return @{ ok = $false; output = ""; reason = "ssh_timeout" }
        }
        $text = ""
        if (Test-Path $outFile) { $text = (Get-Content $outFile -Raw -ErrorAction SilentlyContinue) }
        if ([string]::IsNullOrWhiteSpace($text)) {
            $errHead = ""
            if (Test-Path $errFile) {
                $errHead = ((Get-Content $errFile -Raw -ErrorAction SilentlyContinue) -split "`r?`n" | Select-Object -First 1)
                if ($errHead -ne $null -and $errHead.Length -gt 80) { $errHead = $errHead.Substring(0, 80) }
            }
            return @{ ok = $false; output = ""; reason = "ssh_empty_output:" + $errHead }
        }
        return @{ ok = $true; output = $text; reason = "" }
    } catch {
        return @{ ok = $false; output = ""; reason = "ssh_spawn_failed" }
    } finally {
        Remove-Item $outFile -ErrorAction SilentlyContinue
        Remove-Item $errFile -ErrorAction SilentlyContinue
    }
}

function Get-MsiTelemetry {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty LoadPercentage
    $freeMb = [int][Math]::Round($os.FreePhysicalMemory / 1024)
    $totalMb = [int][Math]::Round($os.TotalVisibleMemorySize / 1024)
    $freePct = 0.0
    if ($totalMb -gt 0) { $freePct = [Math]::Round(100.0 * $freeMb / $totalMb, 1) }

    $services = @{}
    $checks = @(
        @{ name = "studio";    url = "http://127.0.0.1:7340/api/health"; kind = "http" },
        @{ name = "gateway";   url = "http://127.0.0.1:8001/health";     kind = "http" },
        @{ name = "hub";       url = "http://127.0.0.1:8000/";           kind = "http" },
        @{ name = "router";    url = "http://127.0.0.1:9001/";           kind = "http" },
        @{ name = "dispatch";  url = "http://127.0.0.1:9002/";           kind = "http404live" },
        @{ name = "chatdev";   url = "http://127.0.0.1:7338/";           kind = "http" },
        @{ name = "devmentor"; url = "http://127.0.0.1:7337/";           kind = "http" },
        @{ name = "ollama";    url = "http://127.0.0.1:11434/api/tags";   kind = "http" }
    )
    foreach ($c in $checks) {
        $res = Get-HttpStatus $c.url 3
        if ($c.kind -eq "http404live") {
            if ($res.status -eq 404) { $services[$c.name] = "up" }
            elseif ($res.status -ne $null) { $services[$c.name] = "down" }
            else { $services[$c.name] = "unknown" }
        } else {
            if ($res.ok) { $services[$c.name] = "up" }
            elseif ($res.status -ne $null) { $services[$c.name] = "down" }
            else { $services[$c.name] = "unknown" }
        }
    }
    # OpenClaw :18789 is a WebSocket/MCP gateway: plain HTTP GET times out.
    # TCP connect is the honest liveness check; never GET / on this seat.
    $clawTcp = Test-TcpPort "127.0.0.1" 18789 2000
    if ($clawTcp -eq "open") { $services["openclaw"] = "up" }
    elseif ($clawTcp -eq "closed") { $services["openclaw"] = "down" }
    else { $services["openclaw"] = "unknown" }

    $ollamaProc = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
    if ($ollamaProc -ne $null -and $services["ollama"] -eq "unknown") {
        $services["ollama"] = "up"
    }

    $tasks = @{}
    $taskNames = @("KiloCore-Public-Gateway", "KiloCore-Studio-Backend", "KiloCore-Mirror-Sync", "KiloCore-Heartbeat-MSI")
    foreach ($name in $taskNames) {
        try {
            $t = Get-ScheduledTask -TaskName $name -ErrorAction Stop
            $tasks[$name] = [string]$t.State
        } catch {
            $tasks[$name] = "not_found"
        }
    }

    return @{
        state = "live"
        ram_free_mb = $freeMb
        ram_total_mb = $totalMb
        ram_free_pct = $freePct
        cpu_load_pct = $cpu
        services = $services
        tasks = $tasks
        note = "MSI-KATANA, probed locally"
    }
}

function Get-I3Telemetry {
    $tcp22 = Test-TcpPort "100.102.251.35" 22 2000
    # Remote read-only probes. Remote shell is cmd by default, so remote
    # commands must contain NO shell metacharacters: no pipes, no redirects.
    # Each probe is one simple PowerShell expression returning a bare value.
    $rig = @{
        state = "unavailable"
        tcp22 = $tcp22
        ssh = "not_attempted"
        ram_free_mb = $null
        ram_total_mb = $null
        cpu_load_pct = $null
        services = @{}
        tasks = @{}
        seats = ""
        note = ""
    }
    $sshExe = "ssh"
    if (Test-Path $GitSsh) { $sshExe = $GitSsh }
    $free = Invoke-SshProbe $sshExe "i3" 'powershell -NoProfile -Command (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory' $SshTimeoutMs
    if (-not $free.ok) {
        $free = Invoke-SshProbe $sshExe "i3-tailscale" 'powershell -NoProfile -Command (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory' $SshTimeoutMs
    }
    if (-not $free.ok) {
        $rig.ssh = "failed"
        $rig.note = "SSH session unusable from session-0 (" + $free.reason + "); :7337 TCP also unreachable at survey time"
        return $rig
    }
    $rig.ssh = "ok"
    $freeLine = ($free.output -split "`r?`n" | Where-Object { $_ -match "^\d+$" } | Select-Object -First 1)
    $total = Invoke-SshProbe $sshExe "i3" 'powershell -NoProfile -Command (Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize' $SshTimeoutMs
    $totalLine = ""
    if ($total.ok) {
        $totalLine = ($total.output -split "`r?`n" | Where-Object { $_ -match "^\d+$" } | Select-Object -First 1)
    }
    $procs = Invoke-SshProbe $sshExe "i3" 'powershell -NoProfile -Command (Get-Process -Name claude,ollama,GameAttract -ErrorAction SilentlyContinue).ProcessName' $SshTimeoutMs
    if ($freeLine -match "^\d+$" -and $totalLine -match "^\d+$") {
        $rig.ram_free_mb = [int][Math]::Round([double]$freeLine / 1024)
        $rig.ram_total_mb = [int][Math]::Round([double]$totalLine / 1024)
        $rig.state = "live"
        $rig.note = "SSH session works; GameAttract director state not yet probed (no known endpoint)"
    } else {
        $rig.state = "unknown"
        $rig.note = "SSH session works but memory lines unparseable"
    }
    if ($procs.ok) {
        $names = ($procs.output -split "`r?`n" | Where-Object { $_.Trim() -ne "" }) -join ","
        if ($names -ne "") { $rig.seats = $names }
    }
    return $rig
}

function Get-L9Telemetry {
    $rig = @{
        state = "unavailable"
        ssh = "not_attempted"
        ram_free_mb = $null
        ram_total_mb = $null
        cpu_load_pct = $null
        services = @{}
        tasks = @{}
        note = ""
    }
    # L9 is off tailnet: LAN alias only, via Git's bundled ssh.exe (MSI
    # Windows OpenSSH returns exit 255). Remote shell is cmd by default, so
    # remote commands contain NO shell metacharacters (no pipes/redirects).
    # Windows form first; Linux `free -m` fallback (parsed locally, no grep).
    $sshExe = "ssh"
    if (Test-Path $GitSsh) { $sshExe = $GitSsh }
    $free = Invoke-SshProbe $sshExe "kilodesktop" 'powershell -NoProfile -Command (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory' $SshTimeoutMs
    if (-not $free.ok) {
        $rig.ssh = "failed"
        $rig.note = "LAN SSH unreachable (" + $free.reason + ")"
        return $rig
    }
    $rig.ssh = "ok"
    $freeLine = ($free.output -split "`r?`n" | Where-Object { $_ -match "^\d+$" } | Select-Object -First 1)
    if ($freeLine -match "^\d+$") {
        $total = Invoke-SshProbe $sshExe "kilodesktop" 'powershell -NoProfile -Command (Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize' $SshTimeoutMs
        $totalLine = ""
        if ($total.ok) {
            $totalLine = ($total.output -split "`r?`n" | Where-Object { $_ -match "^\d+$" } | Select-Object -First 1)
        }
        if ($totalLine -match "^\d+$") {
            $rig.ram_free_mb = [int][Math]::Round([double]$freeLine / 1024)
            $rig.ram_total_mb = [int][Math]::Round([double]$totalLine / 1024)
            $rig.state = "live"
            $rig.note = "LAN SSH works; memory from CIM"
            return $rig
        }
    }
    $freeUnix = Invoke-SshProbe $sshExe "kilodesktop" 'free -m' $SshTimeoutMs
    $memLine = ""
    if ($freeUnix.ok) {
        $memLine = ($freeUnix.output -split "`r?`n" | Where-Object { $_ -match "^\s*Mem:" } | Select-Object -First 1)
    }
    if ($memLine -match "Mem:\s+(\d+)\s+(\d+)\s+(\d+)") {
        $rig.ram_total_mb = [int]$Matches[1]
        $rig.ram_free_mb = [int]$Matches[3]
        $rig.state = "live"
        $rig.note = "LAN SSH works; memory from free(1)"
    } else {
        $rig.state = "live"
        $rig.note = "LAN SSH works; memory not parsed (unknown shell layout)"
    }
    return $rig
}

function Get-XanaduTelemetry {
    # HTTP ONLY. Never SSH to Xanadu - the pause stands until Keath lifts it.
    $rig = @{
        state = "unavailable"
        services = @{}
        tasks = @{}
        note = "HTTP only - SSH pause stands"
    }
    $res = Get-HttpStatus "http://100.74.243.72:8000/status-json.xsl" 5
    if ($res.ok) {
        try {
            $body = (Invoke-WebRequest -Uri "http://100.74.243.72:8000/status-json.xsl" -UseBasicParsing -TimeoutSec 5).Content | ConvertFrom-Json
            $rig.state = "live"
            $rig.services["icecast"] = "up"
            $rig.note = "Icecast " + [string]$body.icestats.server_id + ", started " + [string]$body.icestats.server_start
        } catch {
            $rig.state = "live"
            $rig.services["icecast"] = "up"
            $rig.note = "Icecast HTTP 200, status body unparseable"
        }
    } else {
        $rig.services["icecast"] = "unknown"
        $rig.note = "Icecast status-json unreachable (HTTP only - SSH pause stands)"
    }
    return $rig
}

$now = [DateTime]::UtcNow
$snapshot = @{
    schema = "kilocore.fleet-telemetry.v1"
    generated_at = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
    generated_unix_ms = [long]([DateTimeOffset]$now).ToUnixTimeMilliseconds()
    probe_host = "MSI-KATANA"
    rigs = @{
        msi = (Get-MsiTelemetry)
        i3 = (Get-I3Telemetry)
        l9 = (Get-L9Telemetry)
        xanadu = (Get-XanaduTelemetry)
    }
}

$dir = Split-Path $SnapshotPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$tmp = $SnapshotPath + ".tmp"
$json = $snapshot | ConvertTo-Json -Depth 6
# BOM-less UTF8: Godot's JSON parser must not see a BOM.
[System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding $false))
Move-Item -Path $tmp -Destination $SnapshotPath -Force
Write-Output ("fleet-telemetry written: " + $SnapshotPath)
