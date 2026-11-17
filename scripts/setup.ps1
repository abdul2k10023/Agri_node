# Compatibility entry point. New checkouts should use install.ps1.
[CmdletBinding()]
param([switch]$InstallHostTools, [switch]$FullTooling, [string[]]$RepairDependency = @())
$ErrorActionPreference = 'Stop'
Write-Host 'setup.ps1 now forwards to the unified install.ps1 (host tools and project setup).'
& (Join-Path $PSScriptRoot 'install.ps1') -FullTooling:$FullTooling -RepairDependency $RepairDependency

