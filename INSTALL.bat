@echo off
rem Prince of Persia: The Warrior Within (Steam) - installs the patch in this folder.
rem It runs patcher\KoPatch.ps1 with Windows PowerShell; open that file in Notepad to see what it does.
if not exist "%~dp0patcher\KoPatch.ps1" (
    echo Extract the whole ZIP file to a folder first, then run INSTALL.bat from there.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0patcher\KoPatch.ps1" -Mode install %*
set KOPATCH_RC=%errorlevel%
if not "%KOPATCH_RC%"=="0" if not "%KOPATCH_RC%"=="2" pause
exit /b %KOPATCH_RC%
