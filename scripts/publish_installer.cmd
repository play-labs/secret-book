@echo off
setlocal

set "ROOT_DIR=%~dp0.."
pushd "%ROOT_DIR%"

call "%ROOT_DIR%\scripts\publish.cmd"
if errorlevel 1 goto :fail

call :resolve_iscc
if not defined ISCC_CMD (
  echo Inno Setup not found.
  echo Please install Inno Setup 6, then run this script again.
  echo Download: https://jrsoftware.org/isinfo.php
  goto :fail_with_code_1
)

echo Building Windows installer...
call "%ISCC_CMD%" "%ROOT_DIR%\installer\secret_book.iss"
if errorlevel 1 goto :fail

echo.
echo Installer completed successfully.
echo Output: %ROOT_DIR%\dist\installer

goto :done

:resolve_iscc
where iscc >nul 2>nul
if %errorlevel%==0 (
  set "ISCC_CMD=iscc"
  exit /b 0
)

if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
  set "ISCC_CMD=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
  exit /b 0
)

if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
  set "ISCC_CMD=C:\Program Files\Inno Setup 6\ISCC.exe"
  exit /b 0
)

if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" (
  set "ISCC_CMD=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
  exit /b 0
)

exit /b 1

:fail_with_code_1
set "EXIT_CODE=1"
goto :cleanup

:fail
set "EXIT_CODE=%errorlevel%"
goto :cleanup

:done
set "EXIT_CODE=0"

:cleanup
popd
endlocal & exit /b %EXIT_CODE%