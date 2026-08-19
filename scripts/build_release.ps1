[CmdletBinding()]
param()

# Backward-compatible entry point. New builds should use build_app.ps1.
& (Join-Path $PSScriptRoot 'build_app.ps1') -Mode Release
if (-not $?) { exit 1 }
