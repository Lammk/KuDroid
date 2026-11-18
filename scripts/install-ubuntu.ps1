[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu-26.04',
    [string]$LinuxUser = 'kudroid',
    [string]$ArchivePath
)
$ErrorActionPreference = 'Stop'
$arguments = @("$PSScriptRoot\install-ubuntu.py", '--distribution', $Distribution, '--user', $LinuxUser)
if ($ArchivePath) { $arguments += @('--archive', $ArchivePath) }
& python @arguments
exit $LASTEXITCODE
