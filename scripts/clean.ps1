# Remove generated firmware/build files; keep downloaded dependencies and tools.
[CmdletBinding(SupportsShouldProcess = $true)]
param()
. (Join-Path $PSScriptRoot 'common.ps1')
$buildPath = Assert-ManagedDirectory (Join-Path $ProjectRoot 'build') $ProjectRoot
if ($PSCmdlet.ShouldProcess($buildPath, 'Remove generated build directory')) {
    $operationLock = Enter-ProjectOperation 'clean'
    try { Remove-ProjectBuild } finally { $operationLock.Dispose() }
}
