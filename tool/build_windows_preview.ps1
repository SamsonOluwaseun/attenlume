# Builds a Windows preview of Attenlume for hands-on testing (ADR-028).
#
#   powershell -File tool\build_windows_preview.ps1
#   ... -SkipTests        skip flutter analyze and flutter test
#   ... -OutDir <folder>  where builds go (default: ..\attenlume-release\windows)
#   ... -ShareDir <folder> where the test package is copied for other PCs
#                         (default: OneDrive\Attenlume Windows Test; '' for none)
#
# Each build is copied to its own folder named after the version and commit,
# so a preview that is still open never blocks the next build. A portable
# ZIP sits next to it, and the desktop shortcut "Attenlume (preview)" is
# pointed at the newest build. Older builds are kept; delete them by hand.
#
# The test package (Attenlume-Windows-Test) holds the newest build as
# Attenlume.zip with the Visual C++ runtime included, plus the installer,
# uninstaller and READ ME from tool\windows_package. Copy that folder to
# any Windows PC and run "Install Attenlume.cmd".

param(
    [switch]$SkipTests,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\..\attenlume-release\windows'),
    [string]$ShareDir = $(if ($env:OneDrive) { Join-Path $env:OneDrive 'Attenlume Windows Test' } else { '' })
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
    # App-local Visual C++ runtime, so PCs without the redistributable can
    # run the build.
    foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
        Copy-Item (Join-Path $env:SystemRoot "System32\$dll") $target
    }
    Compress-Archive -Path "$target\*" -DestinationPath "$target.zip" -Force

    $package = Join-Path $OutDir 'Attenlume-Windows-Test'
    if (Test-Path $package) { Remove-Item $package -Recurse -Force }
    New-Item -ItemType Directory $package | Out-Null
    Copy-Item "$target.zip" (Join-Path $package 'Attenlume.zip')
    Copy-Item (Join-Path $PSScriptRoot 'windows_package\*') $package
    $built = Get-Date -Format 'd MMMM yyyy HH:mm'
    Set-Content (Join-Path $package 'VERSION.txt') "Attenlume $version, commit $commit, built $built" -Encoding ascii
    if ($ShareDir) {
        # Replace only the package's own files; anything else in the folder stays.
        New-Item -ItemType Directory -Force $ShareDir | Out-Null
        Copy-Item "$package\*" $ShareDir -Force
    }

    $shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Attenlume (preview).lnk'
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
    $link.TargetPath = Join-Path $target 'attenlume.exe'
    $link.WorkingDirectory = $target
    $link.Description = "Attenlume preview $version ($commit)"
    $link.Save()

    Write-Host ''
    Write-Host "Preview ready: $target\attenlume.exe"
    Write-Host "Portable ZIP:  $target.zip"
    Write-Host "Test package:  $package"
    if ($ShareDir) { Write-Host "Shared copy:   $ShareDir" }
    Write-Host "Shortcut:      $shortcut"
    Write-Host "App data:      $env:LOCALAPPDATA\Samlytics\Attenlume"
}
finally {
    Pop-Location
}
