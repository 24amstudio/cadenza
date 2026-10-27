@echo off
setlocal
set "APP_HOME=%~dp0"
set "GRADLE_USER_HOME=%APP_HOME%..\..\.cache\gradle"
set "TEMP=%APP_HOME%..\..\.cache\tmp"
set "TMP=%TEMP%"
if not exist "%TEMP%" mkdir "%TEMP%"
set "JAVA_COMMAND=java.exe"
if defined JAVA_HOME set "JAVA_COMMAND=%JAVA_HOME%\bin\java.exe"
"%JAVA_COMMAND%" -classpath "%APP_HOME%gradle\wrapper\gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain %*
exit /b %ERRORLEVEL%
