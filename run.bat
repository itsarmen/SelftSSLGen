@echo off
setlocal EnableExtensions
set "SELF_DIR=%~dp0"
set "SELF_DIR=%SELF_DIR:~0,-1%"
set "BASH="

if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "BASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if not defined BASH for /f "delims=" %%i in ('where bash.exe 2^>nul') do if not defined BASH set "BASH=%%i"

if not defined BASH (
  echo Git Bash not found.
  echo Install Git for Windows: https://git-scm.com/download/win
  pause
  exit /b 1
)

"%BASH%" -lc "cd \"$(cygpath -u '%SELF_DIR%')\" && ./genssl.sh \"$@\"" -- %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" pause
exit /b %RC%
