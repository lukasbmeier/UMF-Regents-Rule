@echo off
rem PUBLISH THE SERVER FROM WINDOWS: tools\publish.sh in Git Bash (see tools\run.cmd).
rem Double-click it, or from a terminal:
rem   tools\publish.cmd              build and publish to `umf`, keeping its data
rem   tools\publish.cmd --fresh      ...wiping its data (a table changed shape)
rem   tools\publish.cmd --codegen    ...and regenerate the client's bindings (needs GODOT in
rem                                  tools\local.env)
setlocal
call "%~dp0run.cmd" tools/publish.sh %*
set "CODE=%ERRORLEVEL%"
rem Opened by a double-click (or from PowerShell), the window would close before it could be read.
echo %cmdcmdline% | findstr /i /c:"%~nx0" >nul && pause
exit /b %CODE%
