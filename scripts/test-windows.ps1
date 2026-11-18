[CmdletBinding()]
param(
    [ValidateSet('all', 'core', 'framework', 'posix', 'arm64', 'probes')][string]$Suite = 'all',
    [switch]$SkipBuild,
    [string]$Distribution = 'Ubuntu-26.04',
    [ValidateRange(1, 128)][int]$Jobs = 6,
    [ValidateRange(1, 86400)][int]$BuildTimeoutSeconds = 600,
    [ValidateRange(1, 86400)][int]$TestTimeoutSeconds = 240
)
$ErrorActionPreference = 'Stop'
$arguments = @("$PSScriptRoot\windows-workflow.py", 'test', '--distribution', $Distribution,
    '--suite', $Suite, '--jobs', $Jobs, '--build-timeout', $BuildTimeoutSeconds,
    '--test-timeout', $TestTimeoutSeconds)
if ($SkipBuild) { $arguments += '--skip-build' }
& python @arguments
exit $LASTEXITCODE
