[CmdletBinding()]
param([Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z]:[\\/]?$')][string]$Drive)

. (Join-Path $PSScriptRoot 'common.ps1')
$destination = $Drive.Substring(0, 2) + '\'
if (!(Test-Path -LiteralPath (Join-Path $destination 'INFO_UF2.TXT'))) {
    throw "No UF2 bootloader found at $destination. Double-reset the board and check its drive letter."
}
$image = Join-Path $ProjectRoot 'build\zephyr\zephyr.uf2'
if (!(Test-Path -LiteralPath $image)) { throw 'Firmware image missing. Run scripts\build.ps1 first.' }
Get-Content -LiteralPath (Join-Path $destination 'INFO_UF2.TXT')
Copy-Item -LiteralPath $image -Destination (Join-Path $destination 'zephyr.uf2')
Write-Host 'Application UF2 copied. The board should reboot and its bootloader drive should disappear.'

