$cadenzaRoot = Split-Path -Parent $PSScriptRoot
$cadenzaCache = Join-Path $cadenzaRoot '.cache'
$cadenzaTools = Join-Path $cadenzaRoot '.tools'

foreach ($cadenzaPath in @($cadenzaCache, $cadenzaTools, (Join-Path $cadenzaCache 'tmp'))) {
    New-Item -ItemType Directory -Path $cadenzaPath -Force | Out-Null
}

$env:TEMP = Join-Path $cadenzaCache 'tmp'
$env:TMP = $env:TEMP
$env:BUN_INSTALL_CACHE_DIR = Join-Path $cadenzaCache 'bun'
$env:GRADLE_USER_HOME = Join-Path $cadenzaCache 'gradle'
$env:ANDROID_USER_HOME = Join-Path $cadenzaCache 'android-user'
$env:ANDROID_HOME = Join-Path $cadenzaTools 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:KONAN_DATA_DIR = Join-Path $cadenzaCache 'konan'
if (Test-Path -LiteralPath (Join-Path $cadenzaTools 'jdk-17\bin\java.exe')) {
    $env:JAVA_HOME = Join-Path $cadenzaTools 'jdk-17'
    $env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:PATH
}

Write-Output "Cadenza caches: $cadenzaCache"
Write-Output "Android SDK location: $env:ANDROID_HOME"
Write-Output 'No toolchains are installed or downloaded by this script.'
