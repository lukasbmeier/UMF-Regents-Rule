@echo off
rem RUN ONE OF THIS PROJECT'S .sh SCRIPTS ON WINDOWS, from cmd, PowerShell or a launcher that
rem calls this (tools\publish.cmd). The scripts are bash; this runs them in Git Bash, which Git for
rem Windows installs (https://git-scm.com/download/win).
rem
rem   tools\run.cmd tests\run_tests.sh
rem   tools\run.cmd tests\integration_test.sh
rem   tools\run.cmd tools\publish.sh --fresh
rem
rem Settings for THIS machine (where Godot is) go in tools\local.env, one NAME="value" per line
rem (copy tools\local.env.example). It is not committed: every machine has its own.
setlocal
if "%~1"=="" goto usage
rem Where Git for Windows puts bash. One line each: a "(x86)" inside a bracketed block ends it.
set "GITBASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined GITBASH if exist "%ProgramW6432%\Git\bin\bash.exe" set "GITBASH=%ProgramW6432%\Git\bin\bash.exe"
if not defined GITBASH if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "GITBASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if not defined GITBASH goto nobash
cd /d "%~dp0.."
set "SCRIPT=%~1"
set "SCRIPT=%SCRIPT:\=/%"
set "ARGS="
:collect
shift
if "%~1"=="" goto run
set ARGS=%ARGS% %1
goto collect
:run
"%GITBASH%" tools/run_env.sh "%SCRIPT%" %ARGS%
exit /b %ERRORLEVEL%
:usage
echo usage: tools\run.cmd ^<script.sh^> [arguments]
exit /b 2
:nobash
echo Git Bash was not found. Install Git for Windows: https://git-scm.com/download/win 1>&2
exit /b 1
