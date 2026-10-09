@echo off
rem TAKE THE FOUNDATION'S LATEST: tools\update_from_template.sh in Git Bash (see tools\run.cmd).
rem Pulls the template, regenerates this game's bindings, runs the unit suite. Double-click it.
setlocal
call "%~dp0run.cmd" tools/update_from_template.sh %*
set "CODE=%ERRORLEVEL%"
echo %cmdcmdline% | findstr /i /c:"%~nx0" >nul && pause
exit /b %CODE%
