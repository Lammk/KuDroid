[CmdletBinding()]
param([string]$Distribution = 'Ubuntu-26.04', [switch]$Elevate)
$ErrorActionPreference = 'Stop'
$administrator = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $administrator.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if (-not $Elevate) {
        throw 'Run this script in Administrator PowerShell to configure the WSL USB service relay.'
    }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $repairArguments = @((Get-Command python -ErrorAction Stop).Source,
        (Join-Path $PSScriptRoot 'run-command.py'), '--timeout', '120', $powershell,
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Distribution', $Distribution)
    $launchCommand = '& ' + (($repairArguments | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ' ') +
        '; exit $LASTEXITCODE'
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($launchCommand))
    $repairProcess = Start-Process -FilePath $powershell -Verb RunAs -WindowStyle Hidden -PassThru `
        -ArgumentList @('-NoProfile', '-EncodedCommand', $encodedCommand)
    if (-not $repairProcess.WaitForExit(150000)) { throw 'USB relay repair did not finish within 150 seconds.' }
    $repairProcess.Refresh()
    if ($repairProcess.ExitCode) {
        $statusPath = Join-Path $env:USERPROFILE '.kudroid/usbmux-relay.status'
        if (Test-Path -LiteralPath $statusPath) { Get-Content -LiteralPath $statusPath | Write-Host }
        throw "USB relay repair failed (exit $($repairProcess.ExitCode))."
    }
    exit 0
}
$taskDirectory = Join-Path $env:USERPROFILE '.kudroid'
New-Item -ItemType Directory -Force -Path $taskDirectory | Out-Null
$statusPath = Join-Path $taskDirectory 'usbmux-relay.status'
$status = 'ERROR: relay setup did not finish'
Start-Transcript -Path (Join-Path $taskDirectory 'usbmux-relay.log') -Force | Out-Null
try {
    $routes = & wsl.exe --distribution $Distribution --exec /usr/bin/env ip -json route list default
    if ($LASTEXITCODE) { throw 'Could not read the WSL route.' }
    $gateway = @(($routes -join '') | ConvertFrom-Json)[0].gateway
    $guestOutput = & wsl.exe --distribution $Distribution --exec /usr/bin/env hostname -I
    if ($LASTEXITCODE) { throw 'Could not read the WSL address.' }
    $guest = (($guestOutput -join ' ').Trim() -split '\s+')[0]
    foreach ($address in @($gateway, $guest)) {
        if ([Net.IPAddress]::Parse($address).AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw 'An IPv4 WSL network is required.'
        }
    }
    $listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 27015 -State Listen -ErrorAction SilentlyContinue
    if (-not $listener) { throw 'Apple USB service is not listening. Install Apple Devices or iTunes and connect the phone.' }
    Start-Service iphlpsvc
    & netsh.exe interface portproxy add v4tov4 listenaddress=$gateway listenport=27015 connectaddress=127.0.0.1 connectport=27015
    if ($LASTEXITCODE) { throw 'Could not configure the USB service relay.' }
    $relayListener = Get-NetTCPConnection -LocalAddress $gateway -LocalPort 27015 -State Listen -ErrorAction SilentlyContinue
    if (-not $relayListener) {
        Restart-Service iphlpsvc -ErrorAction Stop
        $listenerDeadline = [DateTime]::UtcNow.AddSeconds(10)
        do {
            Start-Sleep -Milliseconds 200
            $relayListener = Get-NetTCPConnection -LocalAddress $gateway -LocalPort 27015 -State Listen -ErrorAction SilentlyContinue
        } while (-not $relayListener -and [DateTime]::UtcNow -lt $listenerDeadline)
    }
    if (-not $relayListener) { throw 'The configured USB relay did not start listening.' }
    $ruleName = 'Kudroid-Wsl-Usbmux'
    $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -LocalAddress $gateway -RemoteAddress $guest | Out-Null
    } else {
        New-NetFirewallRule -Name $ruleName -DisplayName 'WSL usbmux relay' -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort 27015 -LocalAddress $gateway -RemoteAddress $guest -Profile Any | Out-Null
    }
    @{ Address = ($gateway + ':27015'); GuestAddress = $guest; Distribution = $Distribution } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $taskDirectory 'usbmux-relay.json') -Encoding UTF8
    $status = 'Connected: ' + $gateway + ':27015'
    Write-Output $status
} catch {
    $status = 'ERROR: ' + $_.Exception.Message
    Write-Output $status
    throw
} finally {
    Stop-Transcript | Out-Null
    Set-Content -LiteralPath $statusPath -Value $status
}
