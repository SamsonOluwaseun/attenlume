@echo off
rem Removes the Attenlume test build. Recordings and settings are kept
rem unless you choose to delete them.
setlocal
set "DEST=%LOCALAPPDATA%\Programs\Attenlume"
set "DATA=%LOCALAPPDATA%\Samlytics\Attenlume"

tasklist /fi "imagename eq attenlume.exe" | find /i "attenlume.exe" >nul
if not errorlevel 1 (
  echo Attenlume is open. Close it, then run this again.
  pause
  exit /b 1
)

if exist "%DEST%" rmdir /s /q "%DEST%"
powershell -NoProfile -Command ^
  "foreach ($dir in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {" ^
  "  Remove-Item (Join-Path $dir 'Attenlume (test).lnk') -ErrorAction SilentlyContinue }"
echo Attenlume has been removed.

if exist "%DATA%" (
  echo.
  echo Your recordings, photos and notes are still in:
  echo   %DATA%
  set /p ANSWER=Delete them too? This cannot be undone. Type YES to delete:
  call :maybe_delete
)
pause
exit /b 0

:maybe_delete
if /i "%ANSWER%"=="YES" (
  rmdir /s /q "%DATA%"
  echo Recordings and settings deleted.
) else (
  echo Recordings and settings kept.
)
exit /b 0
