[CmdletBinding()]
param(
    [ValidateSet('Mount', 'Unmount', 'Status', 'EnableAutoMount', 'DisableAutoMount', 'AutoMountStatus')][string]$Action = 'Mount',
    [ValidatePattern('^[D-Zd-z]$')][string]$Drive = 'K',
    [string]$BundleId = 'com.kudroid.shell',
    [string]$Udid,
    [ValidateRange(1024, 65535)][int]$Port = 8765,
    [switch]$ReadOnly,
    [switch]$Open,
    [ValidateRange(1, 240)][int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
$bridgeDirectory = Join-Path $env:USERPROFILE '.kudroid'
$statePath = Join-Path $bridgeDirectory 'iphone-explorer.json'
$devicePython = Join-Path $bridgeDirectory 'device-tools\Scripts\python.exe'
$bridgeScript = Join-Path $PSScriptRoot 'iphone-webdav.py'
$runner = Join-Path $PSScriptRoot 'run-command.py'
$state = $null
$started = $null
$mapped = $false
$mountMutex = $null
$mutexOwned = $false

function Get-BridgeProcess($saved) {
    if (-not $saved) { return $null }
    $candidate = Get-CimInstance Win32_Process -Filter "ProcessId = $($saved.ProcessId)" -ErrorAction SilentlyContinue
    if ($candidate -and $candidate.ExecutablePath -eq $devicePython -and
        $candidate.CommandLine.Contains('iphone-webdav.py') -and
        $candidate.CreationDate.ToUniversalTime().ToString('o') -eq $saved.StartTime) {
        return $candidate
    }
    return $null
}

function Remove-Bridge($saved) {
    $network = New-Object -ComObject WScript.Network
    $connections = $network.EnumNetworkDrives()
    for ($index = 0; $index -lt $connections.Count(); $index += 2) {
        if ($connections.Item($index) -eq "$($saved.Drive):" -and
            $connections.Item($index + 1) -eq $saved.RemotePath) {
            & python $runner --timeout 20 net.exe use "$($saved.Drive):" /delete /y
            if ($LASTEXITCODE) { throw 'Could not disconnect the Explorer drive.' }
        }
    }
    $owned = Get-BridgeProcess $saved
    if ($owned) { Stop-Process -Id $owned.ProcessId }
    Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
}

try {
    if ($Action -in @('EnableAutoMount', 'DisableAutoMount', 'AutoMountStatus')) {
        $operation = @{ EnableAutoMount = 'install'; DisableAutoMount = 'remove'; AutoMountStatus = 'status' }[$Action]
        $autoArguments = @((Join-Path $PSScriptRoot 'iphone-automount.py'), $operation,
            '--drive', $Drive, '--bundle-id', $BundleId, '--port', $Port)
        if ($Udid) { $autoArguments += @('--udid', $Udid) }
        if ($ReadOnly) { $autoArguments += '--readonly' }
        & python $runner --timeout 240 $devicePython @autoArguments
        exit $LASTEXITCODE
    }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mountMutex = [Threading.Mutex]::new($false, ('Local\KudroidExplorer-' + $sid))
    try { $mutexOwned = $mountMutex.WaitOne($TimeoutSeconds * 1000) }
    catch [Threading.AbandonedMutexException] { $mutexOwned = $true }
    if (-not $mutexOwned) { throw 'Another drive operation is still running.' }
    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    }
    if ($Action -eq 'Status') {
        if (-not $state) { Write-Output 'No Explorer connection is configured.'; exit 0 }
        $state | Select-Object Drive,RemotePath,BundleId,ProcessId,@{Name='Running';Expression={ [bool](Get-BridgeProcess $_) }}
        exit 0
    }
    if ($Action -eq 'Unmount') {
        if ($state) { Remove-Bridge $state }
        Write-Output 'Explorer connection stopped.'
        exit 0
    }
    if (-not (Test-Path -LiteralPath $devicePython)) {
        throw 'Run scripts\iphone.ps1 -Action InstallTools first.'
    }
    $Drive = $Drive.ToUpperInvariant()
    if ($state -and (Get-BridgeProcess $state)) {
        if ($state.Drive -ne $Drive -or $state.BundleId -ne $BundleId -or
            $state.Port -ne $Port -or [bool]$state.ReadOnly -ne [bool]$ReadOnly -or ($Udid -and $state.Udid -ne $Udid)) {
            throw 'Another Explorer connection is active. Unmount it before changing connection options.'
        }
        if (Test-Path -LiteralPath "${Drive}:\") {
            Write-Output "Documents is already connected at ${Drive}:\"
            if ($Open) { Start-Process explorer.exe -ArgumentList "${Drive}:\" }
            exit 0
        }
        Remove-Bridge $state
    } elseif ($state) {
        Remove-Bridge $state
    }
    if (Get-PSDrive -Name $Drive -ErrorAction SilentlyContinue) { throw "Drive ${Drive}: is already in use." }
    if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
        throw "Port $Port is already in use. Choose another -Port."
    }
    $resolve = @((Join-Path $PSScriptRoot 'iphone-files.py'), '--resolve-bundle-id',
        '--bundle-id', $BundleId, '--timeout', $TimeoutSeconds)
    if ($Udid) { $resolve += @('--udid', $Udid) }
    $resolved = & python $runner --timeout $TimeoutSeconds $devicePython @resolve
    if ($LASTEXITCODE) { throw 'Could not open the app. Connect, unlock, and trust the phone.' }
    $resolvedBundle = ($resolved -join '').Trim()
    New-Item -ItemType Directory -Path $bridgeDirectory -Force | Out-Null
    $arguments = @('-u', ('"' + $bridgeScript + '"'), '--bundle-id', $resolvedBundle, '--port', $Port)
    if ($Udid) { $arguments += @('--udid', $Udid) }
    if ($ReadOnly) { $arguments += '--readonly' }
    $started = Start-Process -FilePath $devicePython -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $bridgeDirectory 'iphone-explorer.stdout.log') `
        -RedirectStandardError (Join-Path $bridgeDirectory 'iphone-explorer.stderr.log')
    $url = "http://127.0.0.1:$Port/"
    $ready = $false
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $started.Refresh()
        if ($started.HasExited) {
            throw (Get-Content -LiteralPath (Join-Path $bridgeDirectory 'iphone-explorer.stderr.log') -Raw)
        }
        try {
            $response = Invoke-WebRequest -Uri $url -Method Options -UseBasicParsing -TimeoutSec 2
            $ready = $response.StatusCode -eq 200 -and $response.Headers['DAV']
            if ($ready) { break }
        } catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $ready) { throw 'The Documents bridge did not start within its deadline.' }
    & python $runner --timeout $TimeoutSeconds net.exe use "${Drive}:" $url /persistent:no
    if ($LASTEXITCODE) { throw 'Windows could not map the Documents drive.' }
    $mapped = $true
    $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($started.Id)"
    $state = @{
        Drive = $Drive; Port = $Port; BundleId = $BundleId; ResolvedBundleId = $resolvedBundle;
        Udid = $Udid; ReadOnly = [bool]$ReadOnly; ProcessId = $started.Id;
        StartTime = $processInfo.CreationDate.ToUniversalTime().ToString('o');
        RemotePath = "\\127.0.0.1@$Port\DavWWWRoot"; Url = $url
    }
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
    $labelKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\' +
        ($state.RemotePath -replace '\\', '#')
    New-Item -Path $labelKey -Force | Out-Null
    New-ItemProperty -Path $labelKey -Name '_LabelFromReg' -Value 'Kudroid Documents' -PropertyType String -Force | Out-Null
    Write-Output "Documents connected at ${Drive}:\"
    if ($Open) { Start-Process explorer.exe -ArgumentList "${Drive}:\" }
} catch {
    if ($mapped) { & python $runner --timeout 20 net.exe use "${Drive}:" /delete /y }
    if ($started -and -not $started.HasExited) { Stop-Process -Id $started.Id }
    if ($Open) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Kudroid Documents') | Out-Null
    }
    Write-Error $_
    exit 1
} finally {
    if ($mutexOwned) { $mountMutex.ReleaseMutex() }
    if ($mountMutex) { $mountMutex.Dispose() }
}
