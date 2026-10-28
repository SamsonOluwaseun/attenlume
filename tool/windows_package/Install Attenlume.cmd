@echo off
rem Installs the Attenlume test build for this Windows user (no admin needed).
rem Your recordings and settings are kept between installs.
setlocal
set "DEST=%LOCALAPPDATA%\Programs\Attenlume"
set "ZIP=%~dp0Attenlume.zip"

if not exist "%ZIP%" (
  echo Attenlume.zip is missing from this folder.
  pause
  exit /b 1
)

tasklist /fi "imagename eq attenlume.exe" | find /i "attenlume.exe" >nul
if not errorlevel 1 (
  echo Attenlume is open. Close it, then run this installer again.
  pause
  exit /b 1
)

echo Installing Attenlume to %DEST% ...
if exist "%DEST%" rmdir /s /q "%DEST%"
mkdir "%DEST%"
tar -xf "%ZIP%" -C "%DEST%"
if errorlevel 1 (
  echo Could not unpack Attenlume.zip.
  pause
  exit /b 1
)
copy /y "%~dp0VERSION.txt" "%DEST%\VERSION.txt" >nul

powershell -NoProfile -Command ^
  "$w = New-Object -ComObject WScript.Shell;" ^
  "foreach ($dir in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {" ^
  "  $s = $w.CreateShortcut((Join-Path $dir 'Attenlume (test).lnk'));" ^
  "  $s.TargetPath = '%DEST%\attenlume.exe'; $s.WorkingDirectory = '%DEST%';" ^
  "  $s.Description = 'Attenlume test build'; $s.Save() }"

echo.
type "%~dp0VERSION.txt"
echo.
echo Installed. Starting Attenlume...
start "" "%DEST%\attenlume.exe"
timeout /t 3 >nul
