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
set "NUGET_HTTP_CACHE_PATH=%ROOT%\.tools\nuget-http-cache"
set "NUGET_PACKAGES=%ROOT%\.tools\nuget-packages"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%PUB_CACHE%" mkdir "%PUB_CACHE%"
if not exist "%TEMP%" mkdir "%TEMP%"
if not exist "%ANDROID_USER_HOME%" mkdir "%ANDROID_USER_HOME%"
if not exist "%NUGET_HTTP_CACHE_PATH%" mkdir "%NUGET_HTTP_CACHE_PATH%"
if not exist "%NUGET_PACKAGES%" mkdir "%NUGET_PACKAGES%"
call "%ROOT%\.tools\flutter\bin\flutter.bat" %*
exit /b %ERRORLEVEL%
