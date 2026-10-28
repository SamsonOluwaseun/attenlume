# Builds the Windows installer, attenlume-windows-setup.exe (Inno Setup).
#
#   powershell -File tool\build_windows_installer.ps1 [-SkipBuild] [-OutDir <folder>]
#
# Builds the release app (unless -SkipBuild), adds the Visual C++ runtime
# next to it, and compiles tool\windows_installer\attenlume.iss. The setup
# file keeps one fixed name so the README's "latest" download link works.
# Needs Inno Setup 6: winget install JRSoftware.InnoSetup

param(
    [switch]$SkipBuild,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\..\attenlume-release\windows-installer')
)

$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $env:Path += ';C:\dev\flutter\bin'
}
$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found. Run: winget install JRSoftware.InnoSetup' }

Push-Location $repo
try {
    if (-not $SkipBuild) {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
    }
    $version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value)

    # Stage the release build with the app-local Visual C++ runtime.
    $stage = Join-Path $env:TEMP "attenlume-installer-stage"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    Copy-Item 'build\windows\x64\runner\Release' $stage -Recurse
    foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
        Copy-Item (Join-Path $env:SystemRoot "System32\$dll") $stage
    }

    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $OutDir = Resolve-Path $OutDir
    & $iscc /Q "/DAppVersion=$version" "/DSourceDir=$stage" "/DOutputDir=$OutDir" 'tool\windows_installer\attenlume.iss'
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
    Remove-Item $stage -Recurse -Force

    $setup = Join-Path $OutDir 'attenlume-windows-setup.exe'
    Write-Host "Installer: $setup ($([math]::Round((Get-Item $setup).Length / 1MB, 1)) MB, version $version)"
}
finally {
    Pop-Location
}
