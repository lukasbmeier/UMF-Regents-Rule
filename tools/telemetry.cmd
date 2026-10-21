@echo off
rem THE TELEMETRY PAGE: what happened in the game, as charts in your browser (tools\telemetry.sh in Git
rem Bash, see tools\run.cmd). Run it on the machine that hosts. Double-click it; close the window to stop.
setlocal
call "%~dp0run.cmd" tools/telemetry.sh %*
set "CODE=%ERRORLEVEL%"
echo %cmdcmdline% | findstr /i /c:"%~nx0" >nul && pause
exit /b %CODE%
