param([switch]$ReuseAcceptedArm64)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectDirectory
$version = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)').Groups[1].Value
if (!$version) { throw 'Expected a semantic version with a build number in pubspec.yaml' }
$outputDirectory = Join-Path $projectDirectory "releases/$version/distribution"
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$logDirectory = Join-Path $projectDirectory "releases/$version/distribution-logs"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$flutterExecutable = (Get-Command flutter -ErrorAction Stop).Source
$symbols = Join-Path $projectDirectory "releases/$version/distribution-symbols"
$targets = @(
    @{ Name='arm64-v8a'; Platform='android-arm64' },
    @{ Name='x86_64'; Platform='android-x64' },
    @{ Name='universal'; Platform='android-arm,android-arm64,android-x64' }
)
$artifacts = @()
foreach ($target in $targets) {
    $destination = Join-Path $outputDirectory "Kamico-$version-android-$($target.Name).apk"
    $acceptedArm64 = Join-Path $projectDirectory "releases/$version/app-arm64-release.apk"
    if ($ReuseAcceptedArm64 -and $target.Name -eq 'arm64-v8a' -and (Test-Path -LiteralPath $acceptedArm64)) {
        Copy-Item -LiteralPath $acceptedArm64 -Destination $destination
        $artifacts += $destination
        Write-Output "Reused accepted ARM64 APK: $destination"
        continue
    }
    $arguments = @('build','apk','--release','--no-pub',"--target-platform=$($target.Platform)","--split-debug-info=$symbols",'-Pdisable-abi-filtering=true')
    if ($target.Name -ne 'universal') { $arguments += "-PjmAbi=$($target.Name)" }
    & $flutterExecutable @arguments *> (Join-Path $logDirectory "build-$($target.Name).log")
    if ($LASTEXITCODE -ne 0) { Get-Content (Join-Path $logDirectory "build-$($target.Name).log") -Tail 45; throw "APK build failed: $($target.Name)" }
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination $destination
    $artifacts += $destination
    Write-Output "Built: $destination"
}
Get-FileHash -LiteralPath $artifacts -Algorithm SHA256
