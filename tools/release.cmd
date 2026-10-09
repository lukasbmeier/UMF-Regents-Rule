@echo off
rem MAKE A BUILD TO SEND TO FRIENDS: tools\release.sh in Git Bash (see tools\run.cmd). Exports and
rem tests both builds, records the build's compatibility snapshot, and zips the client to
rem build\releases\. Double-click it.
setlocal
call "%~dp0run.cmd" tools/release.sh %*
set "CODE=%ERRORLEVEL%"
echo %cmdcmdline% | findstr /i /c:"%~nx0" >nul && pause
exit /b %CODE%
