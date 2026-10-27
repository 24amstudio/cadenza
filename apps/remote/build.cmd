@echo off
setlocal
call "%~dp0..\..\tools\windows-env.cmd"
if not exist "%ANDROID_HOME%\platforms\android-37.0\android.jar" (
  echo Android SDK platform android-37.0 is missing. See docs/BUILDING.md. Nothing was downloaded.
  exit /b 2
)
where javac >nul 2>nul
if errorlevel 1 (
  echo An existing JDK 17+ is required. Add its bin directory to PATH.
  exit /b 2
)
set "CADENZA_VARIANT=%~1"
if not defined CADENZA_VARIANT set "CADENZA_VARIANT=Debug"
if /i not "%CADENZA_VARIANT%"=="Debug" if /i not "%CADENZA_VARIANT%"=="Release" (
  echo Usage: build.cmd [Debug^|Release] [development^|ci^|production]
  exit /b 2
)
set "CADENZA_PROFILE=%~2"
if not defined CADENZA_PROFILE set "CADENZA_PROFILE=development"
if /i "%CADENZA_VARIANT%"=="Debug" if /i "%CADENZA_PROFILE%"=="production" (
  echo Production packaging requires the Release variant.
  exit /b 2
)
pushd "%~dp0"
call "%~dp0gradlew.bat" :app:ktlintCheck :app:testDebugUnitTest :app:lintDebug :app:assemble%CADENZA_VARIANT% -Pcadenza.profile=%CADENZA_PROFILE% --no-daemon
set "CADENZA_RESULT=%ERRORLEVEL%"
popd
exit /b %CADENZA_RESULT%
