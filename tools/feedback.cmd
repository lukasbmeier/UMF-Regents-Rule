@echo off
rem WHAT THE PLAYERS SAID, AND HOW THE GAME RAN FOR THEM: tools\feedback.sh in Git Bash (see
rem tools\run.cmd). Run it on the machine that hosts. Double-click it.
setlocal
call "%~dp0run.cmd" tools/feedback.sh %*
set "CODE=%ERRORLEVEL%"
echo %cmdcmdline% | findstr /i /c:"%~nx0" >nul && pause
exit /b %CODE%
