[CmdletBinding()]
param([ValidatePattern('^COM[0-9]+$')][string]$Port)

. (Join-Path $PSScriptRoot 'common.ps1')
if (!(Test-Path -LiteralPath $ProjectPython)) { throw 'Run scripts\install.ps1 first.' }
if (!$Port) {
    Invoke-Checked $ProjectPython @('-m', 'serial.tools.list_ports', '-v')
    Write-Host 'Run scripts\monitor.ps1 -Port COM<number> to connect.'
    return
}
Write-Host 'Press Esc to quit the monitor. Alternative: Ctrl+T, release, then Q.'
Invoke-Checked $ProjectPython @('-m', 'serial.tools.miniterm', $Port, '115200', '--dtr', '1', '--exit-char', '27')
