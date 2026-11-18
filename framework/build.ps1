[CmdletBinding()]
param(
    [switch]$NoEmbed,
    [switch]$RequireD8,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 240
)
$ErrorActionPreference = 'Stop'
$arguments = @("$PSScriptRoot\build.py", '--timeout', $TimeoutSeconds)
if ($NoEmbed) { $arguments += '--no-embed' }
if ($RequireD8) { $arguments += '--require-d8' }
& python @arguments
exit $LASTEXITCODE
