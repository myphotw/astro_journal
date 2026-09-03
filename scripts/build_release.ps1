[CmdletBinding()]
param(
    [ValidateSet('Android', 'Windows')]
    [string]$TargetPlatform = 'Android'
)

# Backward-compatible entry point. New builds should use build_app.ps1.
& (Join-Path $PSScriptRoot 'build_app.ps1') -Mode Release -TargetPlatform $TargetPlatform
if (-not $?) { exit 1 }
