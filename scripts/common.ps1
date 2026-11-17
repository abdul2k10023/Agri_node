Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$ProjectPython = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
$ProjectZephyr = Join-Path $ProjectRoot 'deps\zephyr'
$ProjectSdkVersion = '1.0.1'
$ProjectSdk = Join-Path $ProjectRoot ".tools\zephyr-sdk-$ProjectSdkVersion"
$ProjectBoard = 'promicro_nrf52840/nrf52840/uf2'

function Update-ProjectPath {
    $directories = @(
        (Join-Path $ProjectRoot '.venv\Scripts'),
        (Join-Path $env:ProgramFiles 'CMake\bin'),
        (Join-Path $env:ProgramFiles '7-Zip')
    )
    $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $wingetPackages) {
        foreach ($package in @('Ninja-build.Ninja_*', 'oss-winget.gperf_*', 'oss-winget.dtc_*')) {
            Get-ChildItem -LiteralPath $wingetPackages -Directory -Filter $package | ForEach-Object {
                $directories += @(Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object Name -In @('ninja.exe', 'gperf.exe', 'dtc.exe') |
                    ForEach-Object { $_.DirectoryName })
            }
        }
    }
    $directories += @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        $env:PATH
    )
    $seen = @{}
    $unique = @()
    foreach ($directory in (($directories -join ';') -split ';')) {
        $directory = $directory.Trim().Trim('"')
        if ($directory -and !$seen.ContainsKey($directory.TrimEnd('\'))) {
            $seen[$directory.TrimEnd('\')] = $true
            $unique += $directory
        }
    }
    $env:PATH = $unique -join ';'
}

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE)." }
}

function Enter-ProjectOperation {
    param([string]$Name)
    $lockPath = Join-Path $ProjectRoot '.workspace.lock'
    try {
        $stream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "Cannot lock this workspace for $Name. Another install/build/clean may be running, or access is denied. Wait for it to finish and retry."
    }
    try {
        $stream.SetLength(0)
        $bytes = [Text.Encoding]::UTF8.GetBytes("$Name | PID $PID | $(Get-Date -Format o)")
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        return $stream
    } catch {
        $stream.Dispose()
        throw
    }
}

function Assert-ProjectEnvironment {
    if (!(Test-Path -LiteralPath $ProjectPython)) {
        throw 'Python environment missing. Run scripts\install.ps1 first.'
    }
    if (!(Test-Path -LiteralPath (Join-Path $ProjectZephyr 'VERSION'))) {
        throw 'Zephyr checkout missing. Run scripts\install.ps1 first.'
    }
}

function Set-ProjectEnvironment {
    Update-ProjectPath
    $env:ZEPHYR_BASE = $ProjectZephyr
    $env:ZEPHYR_TOOLCHAIN_VARIANT = 'zephyr'
    if (Test-Path -LiteralPath (Join-Path $ProjectSdk 'sdk_version')) {
        $env:ZEPHYR_SDK_INSTALL_DIR = $ProjectSdk
    }
    $env:PYTHONUTF8 = '1'
    # Enable long paths for this process's Git children, without changing user Git settings.
    $configCount = 0
    if ($env:GIT_CONFIG_COUNT) { $configCount = [int]$env:GIT_CONFIG_COUNT }
    $longPathsIndex = -1
    for ($index = 0; $index -lt $configCount; $index++) {
        if ([Environment]::GetEnvironmentVariable("GIT_CONFIG_KEY_$index") -eq 'core.longpaths') {
            $longPathsIndex = $index
            break
        }
    }
    if ($longPathsIndex -lt 0) {
        $longPathsIndex = $configCount
        $env:GIT_CONFIG_COUNT = [string]($configCount + 1)
    }
    [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$longPathsIndex", 'core.longpaths', 'Process')
    [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$longPathsIndex", 'true', 'Process')
}

function Assert-ManagedDirectory {
    param([string]$Path, [string]$Parent)
    $absolutePath = [IO.Path]::GetFullPath($Path)
    $absoluteParent = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (!$absolutePath.StartsWith($absoluteParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing operation outside $absoluteParent"
    }
    $cursor = $absolutePath
    while ($cursor.Length -ge $absoluteParent.TrimEnd('\').Length) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Refusing operation through a symbolic link or junction: $cursor"
            }
        }
        $cursor = Split-Path -Parent $cursor
        if (!$cursor) { break }
    }
    return $absolutePath
}

function Remove-ProjectBuild {
    $buildPath = Assert-ManagedDirectory (Join-Path $ProjectRoot 'build') $ProjectRoot
    if (!(Test-Path -LiteralPath $buildPath)) {
        Write-Host 'Build directory is already clean.'
        return
    }
    $links = @(Get-ChildItem -LiteralPath $buildPath -Recurse -Force -Attributes ReparsePoint)
    if ($links.Count) { throw 'Refusing to clean a build directory containing symbolic links or junctions.' }
    Write-Host "Removing generated files: $buildPath"
    Remove-Item -LiteralPath $buildPath -Recurse -Force
}

Update-ProjectPath

