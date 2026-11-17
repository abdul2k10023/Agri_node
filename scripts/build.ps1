[CmdletBinding()]
param([switch]$Pristine)

. (Join-Path $PSScriptRoot 'common.ps1')
$operationLock = Enter-ProjectOperation 'build'

Push-Location $ProjectRoot
try {
    Assert-ProjectEnvironment
    Set-ProjectEnvironment
    if ($Pristine) { Remove-ProjectBuild }
    $buildArguments = @('-m', 'west', 'build', '-p', 'auto',
        '-b', $ProjectBoard, '-d', 'build', 'firmware')
    if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot 'build\build.ninja'))) {
        $buildArguments += @('--', '-GNinja', '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON')
    }
    Invoke-Checked $ProjectPython $buildArguments
    $image = Join-Path $ProjectRoot 'build\zephyr\zephyr.uf2'
    if (!(Test-Path -LiteralPath $image)) { throw 'Build did not produce zephyr.uf2.' }
    Write-Host "UF2 ready: $image"
} finally {
    Pop-Location
    $operationLock.Dispose()
}

