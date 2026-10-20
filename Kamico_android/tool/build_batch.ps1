param(
    [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory=$true)][ValidateRange(2,99999)][int]$BuildNumber,
    [ValidateSet('both','release','debug','profile')][string]$Mode = 'both',
    [switch]$AnalyzeSize
)
$ErrorActionPreference = 'Stop'
if ($AnalyzeSize -and $Mode -ne 'release') { throw 'AnalyzeSize requires -Mode release' }
$projectDirectory = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectDirectory
$manifest = Get-Content -LiteralPath 'pubspec.yaml' -Raw
$manifest = [regex]::Replace($manifest, '(?m)^version:.*$', [System.Text.RegularExpressions.MatchEvaluator]{param($match) "version: ${Version}+${BuildNumber}"})
Set-Content -LiteralPath 'pubspec.yaml' -Value $manifest.TrimEnd() -Encoding utf8
Set-Content -LiteralPath 'lib/app_version.dart' -Value "const appVersion = '$Version';" -Encoding utf8
$localProperties = Get-Content -LiteralPath 'android/local.properties' -Raw
$flutterExecutable = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (!$flutterExecutable) {
    $flutterSdk = [regex]::Match($localProperties, '(?m)^flutter.sdk=(.+)$').Groups[1].Value.Trim().Replace('\\', '\')
    $flutterExecutable = Join-Path $flutterSdk 'bin/flutter.bat'
}
$localProperties = [regex]::Replace($localProperties, '(?m)^flutter.versionName=.*$', [System.Text.RegularExpressions.MatchEvaluator]{param($match) "flutter.versionName=$Version"})
$localProperties = [regex]::Replace($localProperties, '(?m)^flutter.versionCode=.*$', [System.Text.RegularExpressions.MatchEvaluator]{param($match) "flutter.versionCode=$BuildNumber"})
Set-Content -LiteralPath 'android/local.properties' -Value $localProperties -Encoding utf8
$artifactDirectory = Join-Path $projectDirectory "releases/$Version"
New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
$buildModes = if ($Mode -eq 'both') { @('release', 'debug') } else { @($Mode) }
$artifacts = @()
foreach ($buildMode in $buildModes) {
    $buildArguments = @('build','apk',"--$buildMode",'--no-pub','--target-platform=android-arm64','-PjmAbi=arm64-v8a','-Pdisable-abi-filtering=true')
    if ($buildMode -eq 'release') {
        if ($AnalyzeSize) { $buildArguments += @('--analyze-size',"--code-size-directory=$artifactDirectory/size-analysis") }
        else { $buildArguments += "--split-debug-info=$artifactDirectory/symbols" }
    }
    & $flutterExecutable @buildArguments *> (Join-Path $artifactDirectory "build-$buildMode.log")
    if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath (Join-Path $artifactDirectory "build-$buildMode.log") -Tail 60; throw "Android $buildMode build failed" }
    $artifact = Join-Path $artifactDirectory "app-arm64-$buildMode.apk"
    Copy-Item -LiteralPath "build/app/outputs/flutter-apk/app-$buildMode.apk" -Destination $artifact
    $artifacts += $artifact
}
& tar -a -cf (Join-Path $artifactDirectory 'source.zip') --exclude=android/.gradle --exclude=android/.kotlin --exclude=android/app/.cxx --exclude=android/app/build --exclude=android/local.properties --exclude=android/key.properties --exclude=*.jks --exclude=*.keystore --exclude=tool/baseline15 --exclude=tool/__pycache__ lib test tool assets artwork android windows pubspec.yaml pubspec.lock README.md LICENSE THIRD_PARTY_NOTICES.md third_party
if ($LASTEXITCODE -ne 0) { throw 'Source archive failed' }
Get-FileHash -LiteralPath $artifacts -Algorithm SHA256
