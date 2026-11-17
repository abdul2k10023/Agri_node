<#
.SYNOPSIS
Installs host tools, isolated Python tools, pinned Zephyr sources and the ARM SDK.
.DESCRIPTION
Run in a normal Windows PowerShell with internet access. Rerunning is supported.
-RepairDependency <west-project-name> discards changes in that downloaded dependency.
#>
[CmdletBinding()]
param([switch]$FullTooling, [string[]]$RepairDependency = @())
. (Join-Path $PSScriptRoot 'common.ps1')

function Find-Python312 {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:ProgramFiles 'Python312\python.exe')
    )
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source -notlike '*\Microsoft\WindowsApps\*') {
        $candidates += $command.Source
    }
    foreach ($candidate in $candidates) {
        if (!(Test-Path -LiteralPath $candidate)) { continue }
        try {
            $version = & $candidate -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
            if ($LASTEXITCODE -eq 0 -and "$version" -eq '3.12') {
                return @{ Program = $candidate; Prefix = @() }
            }
        } catch { continue }
    }
    if (Get-Command py -ErrorAction SilentlyContinue) {
        try {
            $version = & py -3.12 -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
            if ($LASTEXITCODE -eq 0 -and "$version" -eq '3.12') {
                return @{ Program = 'py'; Prefix = @('-3.12') }
            }
        } catch { return $null }
    }
    return $null
}

function Test-HostTool {
    param([hashtable]$Spec)
    if (!(Get-Command $Spec.Command -ErrorAction SilentlyContinue)) { return $false }
    try {
        $versionArguments = $Spec.VersionArguments
        $output = & $Spec.Command @versionArguments 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        if ($Spec.Minimum) {
            $match = [regex]::Match(($output -join ' '), '\d+\.\d+(?:\.\d+)?')
            return $match.Success -and ([version]$match.Value -ge [version]$Spec.Minimum)
        }
        return $true
    } catch { return $false }
}

function Install-HostPackage {
    param([string]$Package)
    if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is missing. Install Microsoft App Installer, or install the host tools listed in README.md, then rerun.'
    }
    Write-Host "Installing host package: $Package"
    # An already-installed package can produce a nonzero winget exit code.
    # Validate the real executable afterwards rather than trusting that code alone.
    & winget install --id $Package --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
    $packageExit = $LASTEXITCODE
    Update-ProjectPath
    Write-Host "winget exit code: $packageExit. Checking installed tool."
}

function Repair-DownloadedDependency {
    param([string]$Name)
    if (@(Get-Process git,git-remote-https -ErrorAction SilentlyContinue).Count) {
        throw 'Close other Git operations before repairing dependencies, then retry.'
    }
    $projects = & $ProjectPython -m west list -f '{name}|{abspath}'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot list dependencies. Run install without -RepairDependency first.' }
    $matches = @($projects | Where-Object { ($_ -split '\|', 2)[0] -ceq $Name })
    if ($matches.Count -ne 1) { throw "Unknown dependency '$Name'. Use a project name from west list." }
    $repository = Assert-ManagedDirectory (($matches[0] -split '\|', 2)[1]) (Join-Path $ProjectRoot 'deps')
    if (!(Test-Path -LiteralPath (Join-Path $repository '.git') -PathType Container)) {
        throw "No downloaded Git repository for '$Name'. Run install without -RepairDependency."
    }
    $gitDirectory = Assert-ManagedDirectory (Join-Path $repository '.git') $repository
    Invoke-Checked 'git' @('-C', $repository, 'rev-parse', '--verify', 'manifest-rev')
    Write-Host "Discarding local changes in downloaded dependency '$Name' and restoring manifest-rev."
    foreach ($lockName in @('index.lock', 'shallow.lock', 'config.lock', 'packed-refs.lock')) {
        $gitLock = Join-Path $gitDirectory $lockName
        if (Test-Path -LiteralPath $gitLock) { Remove-Item -LiteralPath $gitLock -Force }
    }
    Invoke-Checked 'git' @('-C', $repository, 'reset', '--hard', 'manifest-rev')
}

$operationLock = Enter-ProjectOperation 'install'
$stage = 'host tools'
Push-Location $ProjectRoot
try {
    $hostTools = @(
        @{ Command = 'git'; Package = 'Git.Git'; Minimum = $null; VersionArguments = @('--version') },
        @{ Command = 'cmake'; Package = 'Kitware.CMake'; Minimum = '3.28.0'; VersionArguments = @('--version') },
        @{ Command = 'ninja'; Package = 'Ninja-build.Ninja'; Minimum = '1.10'; VersionArguments = @('--version') },
        @{ Command = 'gperf'; Package = 'oss-winget.gperf'; Minimum = $null; VersionArguments = @('--version') },
        @{ Command = 'dtc'; Package = 'oss-winget.dtc'; Minimum = '1.4.6'; VersionArguments = @('--version') },
        @{ Command = '7z'; Package = '7zip.7zip'; Minimum = $null; VersionArguments = @('i') }
    )
    foreach ($spec in $hostTools) {
        if (!(Test-HostTool $spec)) { Install-HostPackage $spec.Package }
        if (!(Test-HostTool $spec)) {
            throw "$($spec.Command) is still unavailable or too old. Check winget's result and run from a normal PowerShell with access to installed programs."
        }
        Write-Host "Ready: $($spec.Command)"
    }
    $hostPython = Find-Python312
    if (!$hostPython) {
        Install-HostPackage 'Python.Python.3.12'
        $hostPython = Find-Python312
    }
    if (!$hostPython) { throw 'Python 3.12 is unavailable. Check its installer result and rerun.' }

    $stage = 'Python virtual environment'
    if (!(Test-Path -LiteralPath $ProjectPython)) {
        Invoke-Checked $hostPython.Program (@($hostPython.Prefix) + @('-m', 'venv', (Join-Path $ProjectRoot '.venv')))
    }
    Invoke-Checked $ProjectPython @('-c', "import sys; assert sys.version_info[:2] == (3, 12), 'Remove the old .venv directory and rerun install.ps1 to recreate it with Python 3.12'")
    Set-ProjectEnvironment
    Invoke-Checked $ProjectPython @('-m', 'pip', 'install', '--disable-pip-version-check', '--prefer-binary', 'west==1.5.0')

    $stage = 'Zephyr workspace'
    if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot '.west'))) {
        Invoke-Checked $ProjectPython @('-m', 'west', 'init', '-l', 'firmware')
    }
    $workspace = & $ProjectPython -m west topdir
    if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath("$workspace") -ne $ProjectRoot) {
        throw 'west resolved another workspace. Check this project''s .west directory.'
    }
    $manifestPath = & $ProjectPython -m west config --local manifest.path
    if ($LASTEXITCODE -ne 0 -or "$manifestPath" -ne 'firmware') {
        throw 'This workspace must use firmware/west.yml. Check .west/config.'
    }
    foreach ($name in $RepairDependency) { Repair-DownloadedDependency $name }

    $stage = 'pinned source downloads'
    Invoke-Checked $ProjectPython @('-m', 'west', 'update', '--narrow', '--fetch-opt=--depth=1')

    $stage = 'Python build dependencies'
    $requirementArguments = @('-r', (Join-Path $ProjectZephyr 'scripts\requirements-base.txt'))
    if ($FullTooling) {
        $requirements = & $ProjectPython -m west packages pip
        if ($LASTEXITCODE -ne 0) { throw 'Could not resolve Python requirements.' }
        $requirementArguments = @()
        foreach ($line in $requirements) {
            if ($line -notmatch '^-r (.+)$') { throw "Unexpected requirements output: $line" }
            $requirementArguments += @('-r', $Matches[1])
        }
    }
    Invoke-Checked $ProjectPython (@('-m', 'pip', 'install', '--disable-pip-version-check', '--prefer-binary') + $requirementArguments)

    $stage = 'ARM SDK'
    $requiredSdkVersion = (Get-Content -LiteralPath (Join-Path $ProjectZephyr 'SDK_VERSION') -Raw).Trim()
    if ($requiredSdkVersion -ne $ProjectSdkVersion) {
        throw "Zephyr requires SDK $requiredSdkVersion. Update ProjectSdkVersion in scripts/common.ps1."
    }
    Invoke-Checked $ProjectPython @('-m', 'west', 'sdk', 'install', '--version', $ProjectSdkVersion,
        '--install-dir', $ProjectSdk, '--gnu-toolchains', 'arm-zephyr-eabi')
    Write-Host 'Install complete. Next: powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1'
} catch {
    Write-Host "Installation stopped during: $stage" -ForegroundColor Red
    Write-Host 'Fix the error above and rerun install.ps1. Completed downloads are reused.'
    Write-Host 'For socket/access errors, use a terminal with network and installed-tool access.'
    Write-Host 'For an interrupted Git checkout, stop other Git operations and use -RepairDependency <project-name>; see README.md.'
    throw
} finally {
    Pop-Location
    $operationLock.Dispose()
}
