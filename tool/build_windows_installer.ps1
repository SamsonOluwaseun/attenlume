# Builds the Windows installer, attenlume-windows-setup.exe (Inno Setup).
#
#   powershell -File tool\build_windows_installer.ps1 [-SkipBuild] [-DirectSupport] [-OutDir <folder>]
#
# Builds the release app (unless -SkipBuild), adds the Visual C++ runtime
# next to it, and compiles tool\windows_installer\attenlume.iss. The setup
# file keeps one fixed name so the README's "latest" download link works.
# Needs Inno Setup 6: winget install JRSoftware.InnoSetup

param(
    [switch]$SkipBuild,
    [switch]$DirectSupport,
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
        $buildArgs = @('build', 'windows', '--release')
        if ($DirectSupport) {
            $buildArgs += '--dart-define=ATTENLUME_SUPPORT_DISTRIBUTION=windows-direct'
        }
        # Windows PowerShell wraps Flutter's informational stderr as ErrorRecord.
        # Use the native exit code to distinguish a build failure from warnings.
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & flutter @buildArgs
            $buildExit = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
        if ($buildExit -ne 0) { throw 'flutter build windows failed' }
    }
    # Check all files that the recursive staging copy could package. Also compare
    # the sole provider with native assets: an overwritten DLL hides a collision.
    $runner = 'build\windows\x64\runner\Release'
    $ggmlBases = @(Get-ChildItem -LiteralPath $runner -Recurse -Filter 'ggml-base.dll' -File)
    $ggmlHashes = @($ggmlBases | Get-FileHash -Algorithm SHA256 | Select-Object -ExpandProperty Hash -Unique)
    if ($ggmlHashes.Count -ne 1) {
        throw "Expected one distinct ggml-base.dll before packaging; found $($ggmlHashes.Count)"
    }
    $nativeBase = 'build\native_assets\windows\ggml-base.dll'
    if (-not (Test-Path -LiteralPath $nativeBase) -or
        $ggmlHashes[0] -ne (Get-FileHash -LiteralPath $nativeBase -Algorithm SHA256).Hash) {
        throw 'Runner ggml-base.dll does not match fllama native assets'
    }
    if (Get-ChildItem -LiteralPath $runner -Recurse -Filter 'ggml-cpu.dll' -File) {
        throw "Whisper's shared ggml-cpu.dll must not be packaged"
    }
    $version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value)

    # Stage the release build with the app-local Visual C++ runtime.
    $stageRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    $stage = [IO.Path]::GetFullPath((Join-Path $stageRoot ("attenlume-installer-" + [guid]::NewGuid().ToString('N'))))
    if (-not $stage.StartsWith($stageRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Installer staging path escapes temporary directory'
    }
    Copy-Item 'build\windows\x64\runner\Release' $stage -Recurse
    foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
        Copy-Item (Join-Path $env:SystemRoot "System32\$dll") $stage
    }

    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $OutDir = Resolve-Path $OutDir
    & $iscc /Q "/DAppVersion=$version" "/DSourceDir=$stage" "/DOutputDir=$OutDir" 'tool\windows_installer\attenlume.iss'
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
    # Recheck the absolute target before recursively removing only our unique stage.
    if ([IO.Path]::GetFullPath($stage).StartsWith($stageRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }

    $setup = Join-Path $OutDir 'attenlume-windows-setup.exe'
    Write-Host "Installer: $setup ($([math]::Round((Get-Item $setup).Length / 1MB, 1)) MB, version $version)"
}
finally {
    Pop-Location
}
