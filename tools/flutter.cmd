@echo off
setlocal
set "ROOT=%~dp0.."
set "APPDATA=%ROOT%\.tools\appdata\Roaming"
set "LOCALAPPDATA=%ROOT%\.tools\appdata\Local"
set "PUB_CACHE=%ROOT%\.tools\pub-cache"
set "TEMP=%ROOT%\.tools\temp"
set "TMP=%ROOT%\.tools\temp"
set "ANDROID_HOME=%ROOT%\.tools\android-sdk"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
set "ANDROID_USER_HOME=%ROOT%\.tools\android-home"
set "GRADLE_USER_HOME=%ROOT%\.tools\gradle"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%PUB_CACHE%" mkdir "%PUB_CACHE%"
if not exist "%TEMP%" mkdir "%TEMP%"
if not exist "%ANDROID_USER_HOME%" mkdir "%ANDROID_USER_HOME%"
call "%ROOT%\.tools\flutter\bin\flutter.bat" %*
exit /b %ERRORLEVEL%
