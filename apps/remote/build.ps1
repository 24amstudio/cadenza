param(
    [ValidateSet('Debug', 'Release')]
    [string]$Variant = 'Debug'
)

$ErrorActionPreference = 'Stop'
$cadenzaRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $cadenzaRoot 'tools\windows-env.ps1')

if (-not (Test-Path -LiteralPath (Join-Path $env:ANDROID_HOME 'platforms\android-37.0\android.jar'))) {
    throw "Android SDK platform android-37.0 is not installed at $env:ANDROID_HOME. See docs/BUILDING.md. Nothing was downloaded."
}
if (-not (Get-Command javac -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'Use an installed JDK 17+ and add its bin directory to PATH. See docs/BUILDING.md.'
}

Push-Location -LiteralPath $PSScriptRoot
try {
    & .\gradlew.bat ':app:ktlintCheck' ':app:testDebugUnitTest' ':app:lintDebug' (':app:assemble' + $Variant) --no-daemon
    if ($LASTEXITCODE -ne 0) { throw 'Android checks or build failed.' }
} finally {
    Pop-Location
}
