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
# Windows PowerShell 5.1 writes a UTF-8 BOM for -Encoding utf8, which pollutes
# the tracked version files. Write UTF-8 without BOM explicitly instead.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$manifest = Get-Content -LiteralPath 'pubspec.yaml' -Raw
$manifest = [regex]::Replace($manifest, '(?m)^version:.*$', [System.Text.RegularExpressions.MatchEvaluator]{param($match) "version: ${Version}+${BuildNumber}"})
[System.IO.File]::WriteAllText((Join-Path $projectDirectory 'pubspec.yaml'), $manifest.TrimEnd(), $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $projectDirectory 'lib/app_version.dart'), "const appVersion = '$Version';", $utf8NoBom)
$localProperties = Get-Content -LiteralPath 'android/local.properties' -Raw
$flutterExecutable = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (!$flutterExecutable) {
    $flutterSdk = [regex]::Match($localProperties, '(?m)^flutter.sdk=(.+)$').Groups[1].Value.Trim().Replace('\\', '\')
    $flutterExecutable = Join-Path $flutterSdk 'bin/flutter.bat'
}
$localProperties = [regex]::Replace($localProperties, '(?m)^flutter.versionName=.*$', [System.Text.RegularExpressions.MatchEvaluator]{param($match) "flutter.versionName=$Version"})
$localProperties = [regex]::Replace($localProperties, '(?m)^flutter.versionCode=.*$', [System.Text.RegularExpressions.MatchEvaluator]{param($match) "flutter.versionCode=$BuildNumber"})
[System.IO.File]::WriteAllText((Join-Path $projectDirectory 'android/local.properties'), $localProperties, $utf8NoBom)
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
    $buildLog = Join-Path $artifactDirectory "build-$buildMode.log"
    # flutter.bat writes its storage-mirror warning to stderr. PowerShell 5.1
    # turns redirected native stderr into a terminating error under 'Stop', so
    # relax the preference for this call and read the real exit code instead.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $flutterExecutable @buildArguments *> $buildLog
        $buildExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($buildExitCode -ne 0) { Get-Content -LiteralPath $buildLog -Tail 60; throw "Android $buildMode build failed" }
    $artifact = Join-Path $artifactDirectory "app-arm64-$buildMode.apk"
    Copy-Item -LiteralPath "build/app/outputs/flutter-apk/app-$buildMode.apk" -Destination $artifact
    $artifacts += $artifact
}
& $env:SystemRoot\System32\tar.exe -a -cf (Join-Path $artifactDirectory 'source.zip') --exclude=android/.gradle --exclude=android/.kotlin --exclude=android/app/.cxx --exclude=android/app/build --exclude=android/local.properties --exclude=android/key.properties --exclude=*.jks --exclude=*.keystore --exclude=tool/baseline15 --exclude=tool/__pycache__ lib test tool assets artwork android windows pubspec.yaml pubspec.lock README.md LICENSE THIRD_PARTY_NOTICES.md third_party
if ($LASTEXITCODE -ne 0) { throw 'Source archive failed' }
Get-FileHash -LiteralPath $artifacts -Algorithm SHA256
