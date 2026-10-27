@echo off
setlocal
call "%~dp0..\..\tools\windows-env.cmd"
if not exist "%ANDROID_HOME%\platforms\android-37.0\android.jar" (
  echo Android SDK platform android-37.0 is missing. See docs/BUILDING.md. Nothing was downloaded.
  exit /b 2
)
where javac >nul 2>nul
if errorlevel 1 (
  echo JDK 17+ is required. Add its bin directory to PATH.
  exit /b 2
)
pushd "%~dp0"
call "%~dp0gradlew.bat" :app:ktlintCheck :app:testDebugUnitTest :app:testReleaseUnitTest :app:lintDebug :app:lintRelease :app:compileDebugKotlin :app:compileReleaseKotlin --no-daemon --console=plain
set "CADENZA_RESULT=%ERRORLEVEL%"
popd
exit /b %CADENZA_RESULT%
