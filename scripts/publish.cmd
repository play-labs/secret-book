@echo off
setlocal

set "ROOT_DIR=%~dp0.."
pushd "%ROOT_DIR%"

call :resolve_flutter
if not defined FLUTTER_CMD (
  echo Flutter not found in PATH or C:\Flutter\flutter\bin\flutter.bat
  echo Please install Flutter or update your PATH, then try again.
  goto :fail_with_code_1
)

echo Preparing Windows release environment...
call :cleanup_processes
call :run_flutter clean
if errorlevel 1 (
  echo Warning: flutter clean reported an error. Continuing anyway...
)

call :run_flutter pub get
if errorlevel 1 goto :fail

call :patch_super_native_extensions
if errorlevel 1 (
  echo Warning: super_native_extensions patch failed. Continuing anyway...
)

echo Building Windows release package...
call :run_flutter build windows --release --target lib/main.dart
if errorlevel 1 goto :fail

set "BUILD_DIR=%ROOT_DIR%\build\windows\x64\runner\Release"
set "OUTPUT_DIR=%ROOT_DIR%\dist\secret_book-windows-release"

if not exist "%BUILD_DIR%\secret_book.exe" (
  echo Release build output not found: %BUILD_DIR%\secret_book.exe
  goto :fail_with_code_1
)

if exist "%OUTPUT_DIR%" (
  echo Cleaning previous publish output...
  rmdir /s /q "%OUTPUT_DIR%"
)

mkdir "%OUTPUT_DIR%"
if errorlevel 1 goto :fail

xcopy "%BUILD_DIR%\*" "%OUTPUT_DIR%\" /E /I /Y >nul
if errorlevel 1 goto :fail

echo.
echo Publish completed successfully.
echo Output: %OUTPUT_DIR%
echo Executable: %OUTPUT_DIR%\secret_book.exe
goto :done

:resolve_flutter
where flutter >nul 2>nul
if %errorlevel%==0 (
  set "FLUTTER_CMD=flutter"
  exit /b 0
)

if exist "C:\Flutter\flutter\bin\flutter.bat" (
  set "FLUTTER_CMD=C:\Flutter\flutter\bin\flutter.bat"
  exit /b 0
)

exit /b 1

:cleanup_processes
echo Stopping leftover build processes...
for %%P in (secret_book cmake ninja) do (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Get-Process '%%P' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue" >nul 2>nul
)
exit /b 0

:run_flutter
if /I "%FLUTTER_CMD%"=="flutter" (
  flutter %*
) else (
  call "%FLUTTER_CMD%" %*
)
exit /b %errorlevel%

:patch_super_native_extensions
set "CARGOKIT_CMAKE=%ROOT_DIR%\windows\flutter\ephemeral\.plugin_symlinks\super_native_extensions\cargokit\cmake\cargokit.cmake"
if not exist "%CARGOKIT_CMAKE%" (
  exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$path = '%CARGOKIT_CMAKE%';" ^
  "$content = Get-Content -Raw -Encoding utf8 $path;" ^
  "$old = \"if(WIN32)`r`n    # REALPATH does not properly resolve symlinks on windows :-/`r`n    execute_process(COMMAND powershell -ExecutionPolicy Bypass -File `\"`${CMAKE_CURRENT_LIST_DIR}/resolve_symlinks.ps1`\" `\"`${cargokit_cmake_root}`\" OUTPUT_VARIABLE cargokit_cmake_root OUTPUT_STRIP_TRAILING_WHITESPACE)`r`nendif()\";" ^
  "$new = \"if(WIN32)`r`n    # Patched by publish.cmd: rely on CMake REALPATH directly.`r`nendif()\";" ^
  "$next = $content.Replace($old, $new);" ^
  "if ($next -ne $content) { [System.IO.File]::WriteAllText($path, $next, (New-Object System.Text.UTF8Encoding($false))) }"
exit /b 0

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
