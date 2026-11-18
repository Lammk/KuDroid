[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')][string]$Configuration,
    [switch]$Run,
    [switch]$Clean,
    [ValidateSet('metal', 'vulkan')][string]$GlesBackend = 'metal',
    [string]$Distribution = 'Ubuntu-26.04',
    [ValidateRange(1, 128)][int]$Jobs = 6,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 600
)
$ErrorActionPreference = 'Stop'
$arguments = @("$PSScriptRoot\windows-workflow.py", 'ios', '--distribution', $Distribution,
    '--gles-backend', $GlesBackend,
    '--jobs', $Jobs, '--build-timeout', $TimeoutSeconds)
if ($Configuration) { $arguments += @('--configuration', $Configuration.ToLowerInvariant()) }
if ($Run) { $arguments += '--run' }
if ($Clean) { $arguments += '--clean' }
& python @arguments
exit $LASTEXITCODE
