[CmdletBinding()]
param(
    [ValidateSet('Devices', 'Apps', 'List', 'Browse', 'Pull', 'Push', 'InstallTools')][string]$Action = 'List',
    [string]$BundleId = 'com.kudroid.shell',
    [string]$RemotePath = '/',
    [string]$LocalPath,
    [string]$Udid,
    [switch]$Container,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 240
)
$ErrorActionPreference = 'Stop'
$tools = Join-Path $env:USERPROFILE '.kudroid\device-tools'
$devicePython = Join-Path $tools 'Scripts\python.exe'
$deadline = "$PSScriptRoot\run-command.py"
if ($Action -eq 'InstallTools') {
    & python $deadline --timeout 120 python -m venv $tools
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    & python $deadline --timeout 900 $devicePython -m pip install 'pymobiledevice3==11.50.3'
    exit $LASTEXITCODE
}
if (-not (Test-Path -LiteralPath $devicePython)) {
    throw 'Device tools missing. Run scripts\iphone.ps1 -Action InstallTools.'
}
if ($Action -eq 'List') {
    $arguments = @("$PSScriptRoot\iphone-files.py", '--bundle-id', $BundleId,
        '--path', $RemotePath, '--timeout', $TimeoutSeconds)
    if ($Udid) { $arguments += @('--udid', $Udid) }
    if ($Container) { $arguments += '--container' }
} else {
    $arguments = @('-m', 'pymobiledevice3')
    if ($Action -notin @('Devices', 'Apps')) {
        $resolveArguments = @("$PSScriptRoot\iphone-files.py", '--resolve-bundle-id',
            '--bundle-id', $BundleId, '--timeout', $TimeoutSeconds)
        if ($Udid) { $resolveArguments += @('--udid', $Udid) }
        $resolved = & python $deadline --timeout $TimeoutSeconds $devicePython @resolveArguments
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
        $BundleId = ($resolved -join '').Trim()
    }
    $transferPath = $RemotePath
    if (-not $Container) { $transferPath = '/Documents/' + $RemotePath.TrimStart('/') }
    switch ($Action) {
        'Devices' { $arguments += @('usbmux', 'list') }
        'Apps' { $arguments += @('apps', 'list', '--type', 'User') }
        'Browse' { $arguments += @('apps', 'afc', $BundleId) }
        'Pull' {
            if (-not $LocalPath) { throw '-LocalPath is required for Pull.' }
            $arguments += @('apps', 'pull', $BundleId, $transferPath, $LocalPath)
        }
        'Push' {
            if (-not $LocalPath) { throw '-LocalPath is required for Push.' }
            if (-not (Test-Path -LiteralPath $LocalPath)) { throw "File not found: $LocalPath" }
            $arguments += @('apps', 'push', $BundleId, $LocalPath, $transferPath)
        }
    }
    if ($Action -notin @('Devices', 'Apps')) {
        if (-not $Container) { $arguments += '--documents' }
        if ($Udid) { $arguments += @('--udid', $Udid) }
    }
    if ($Action -eq 'Apps' -and $Udid) { $arguments += @('--udid', $Udid) }
}
& python $deadline --timeout $TimeoutSeconds $devicePython @arguments
exit $LASTEXITCODE
