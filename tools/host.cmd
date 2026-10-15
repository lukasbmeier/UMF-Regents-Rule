@echo off
rem HOST A GAME FOR PLAYERS ON OTHER MACHINES: tools\host.sh in Git Bash (see tools\run.cmd). Starts
rem SpacetimeDB for other machines if it is not running, and the world's referee (it drives the bots and
rem judges attacks), until you close this window. Double-click it.
setlocal
call "%~dp0run.cmd" tools/host.sh %*
set "CODE=%ERRORLEVEL%"
echo %cmdcmdline% | findstr /i /c:"%~nx0" >nul && pause
exit /b %CODE%
