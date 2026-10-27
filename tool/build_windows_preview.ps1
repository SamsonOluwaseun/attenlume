# Builds a Windows preview of Attenlume for hands-on testing (ADR-028).
#
#   powershell -ExecutionPolicy Bypass -File tool\build_windows_preview.ps1
#   ... -SkipTests        skip flutter analyze and flutter test
#   ... -OutDir <folder>  where builds go (default: ..\attenlume-release\windows)
#
# Each build is copied to its own folder named after the version and commit,
# so a preview that is still open never blocks the next build. A portable
# ZIP sits next to it, and the desktop shortcut "Attenlume (preview)" is
# pointed at the newest build. Older builds are kept; delete them by hand.

param(
    [switch]$SkipTests,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\..\attenlume-release\windows')
)

$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $env:Path += ';C:\dev\flutter\bin'
}
Push-Location $repo
try {
    if (-not $SkipTests) {
        flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze found issues' }
        flutter test
        if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
    }

    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }

    $version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value) -replace '\+', '-b'
    $commit = (git rev-parse --short HEAD).Trim()
    if (git status --porcelain) { $commit += '-dirty' }
    $name = "Attenlume-$version-$commit"

    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $OutDir = Resolve-Path $OutDir
    $target = Join-Path $OutDir $name
    if (Test-Path $target) { $target += '-' + (Get-Date -Format 'HHmmss') }
    Copy-Item 'build\windows\x64\runner\Release' $target -Recurse
    Compress-Archive -Path "$target\*" -DestinationPath "$target.zip" -Force

    $shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Attenlume (preview).lnk'
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
    $link.TargetPath = Join-Path $target 'attenlume.exe'
    $link.WorkingDirectory = $target
    $link.Description = "Attenlume preview $version ($commit)"
    $link.Save()

    Write-Host ''
    Write-Host "Preview ready: $target\attenlume.exe"
    Write-Host "Portable ZIP:  $target.zip"
    Write-Host "Shortcut:      $shortcut"
    Write-Host "App data:      $env:LOCALAPPDATA\Samlytics\Attenlume"
}
finally {
    Pop-Location
}
