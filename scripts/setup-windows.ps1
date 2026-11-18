[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu-26.04',
    [string]$XcodePath,
    [switch]$Configure,
    [ValidateRange(1, 86400)][int]$ToolchainTimeoutSeconds = 3600
)
$ErrorActionPreference = 'Stop'
$arguments = @("$PSScriptRoot\windows-workflow.py", 'setup', '--distribution', $Distribution,
    '--toolchain-timeout', $ToolchainTimeoutSeconds)
if ($XcodePath) { $arguments += @('--xcode', $XcodePath) }
if ($Configure) { $arguments += '--configure' }
& python @arguments
exit $LASTEXITCODE
