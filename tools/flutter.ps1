param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $FlutterArgs
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root '.tools'

$env:APPDATA = Join-Path $tools 'appdata\Roaming'
$env:LOCALAPPDATA = Join-Path $tools 'appdata\Local'
$env:PUB_CACHE = Join-Path $tools 'pub-cache'
$env:TEMP = Join-Path $tools 'temp'
$env:TMP = Join-Path $tools 'temp'
$env:ANDROID_HOME = Join-Path $tools 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_USER_HOME = Join-Path $tools 'android-home'
$env:GRADLE_USER_HOME = Join-Path $tools 'gradle'
$env:NUGET_HTTP_CACHE_PATH = Join-Path $tools 'nuget-http-cache'
$env:NUGET_PACKAGES = Join-Path $tools 'nuget-packages'

foreach ($dir in @($env:APPDATA, $env:LOCALAPPDATA, $env:PUB_CACHE, $env:TEMP, $env:ANDROID_USER_HOME, $env:NUGET_HTTP_CACHE_PATH, $env:NUGET_PACKAGES)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

& (Join-Path $tools 'flutter\bin\flutter.bat') @FlutterArgs
exit $LASTEXITCODE
