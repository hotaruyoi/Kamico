param(
    [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory=$true)][int]$BuildNumber,
    [string]$Baseline = '0.21.0',
    [string]$ExpectedSignerSha256 = 'c9c2e03d943cfa9a1f4ea7f2386075789db7ebb9ae360b035d337594cdcf78b2'
)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$sdkTools = 'D:\Application\Android-SDK\build-tools\35.0.0'
$baselinePath = Join-Path $projectDirectory "docs/artifacts-$Baseline.json"
$expectedSigner = "Signer #1 certificate SHA-256 digest: $ExpectedSignerSha256"
if (Test-Path -LiteralPath $baselinePath) {
    $baselineRecord = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
    $expectedSigner = ($baselineRecord | Where-Object mode -eq 'release').signer
}
$records = foreach ($buildMode in @('release', 'debug')) {
    $apkPath = Join-Path $projectDirectory "releases/$Version/app-arm64-$buildMode.apk"
    $badging = & (Join-Path $sdkTools 'aapt2.exe') dump badging $apkPath
    if ($LASTEXITCODE -ne 0) { throw "Invalid APK: $apkPath" }
    $package = $badging | Where-Object { $_.StartsWith('package:') }
    $label = $badging | Where-Object { $_.StartsWith('application-label:') }
    $debuggable = @($badging | Where-Object { $_ -eq 'application-debuggable' }).Count -gt 0
    $expectedId = if ($buildMode -eq 'debug') { 'app.jmpic.jm_mobile.debug' } else { 'app.jmpic.jm_mobile' }
    $expectedLabel = if ($buildMode -eq 'debug') { 'kamico Debug' } else { 'kamico' }
    if (!$package.Contains("name='$expectedId'") -or !$package.Contains("versionCode='$BuildNumber'") -or !$package.Contains("versionName='$Version'")) { throw "Package/version mismatch: $package" }
    if ($label -ne "application-label:'$expectedLabel'" -or $debuggable -ne ($buildMode -eq 'debug')) { throw "Identity/debug flag mismatch: $buildMode" }
    $native = $badging | Where-Object { $_.StartsWith('native-code:') }
    if ($native.Trim() -ne "native-code: 'arm64-v8a'") { throw "Unexpected ABIs: $native" }
    $minSdk = $badging | Where-Object { $_.StartsWith('minSdkVersion:') }
    if ($minSdk -ne "minSdkVersion:'24'") { throw "Minimum SDK changed: $minSdk" }
    $signing = & (Join-Path $sdkTools 'apksigner.bat') verify --print-certs $apkPath
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $buildMode" }
    $signer = $signing | Where-Object { $_.StartsWith('Signer #1 certificate SHA-256 digest:') }
    if ($signer -ne $expectedSigner) { throw "Certificate differs from accepted baseline: $buildMode" }
    [pscustomobject]@{
        mode = $buildMode
        bytes = (Get-Item -LiteralPath $apkPath).Length
        sha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
        package = $package
        label = $label
        debuggable = $debuggable
        nativeCode = $native
        minSdk = $minSdk
        targetSdk = $badging | Where-Object { $_.StartsWith('targetSdkVersion:') }
        signer = $signer
    }
}
$records | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $projectDirectory "releases/$Version/artifacts.json")
$records | Select-Object mode,bytes,package,debuggable,sha256 | Format-List
