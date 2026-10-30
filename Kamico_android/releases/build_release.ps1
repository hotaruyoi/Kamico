<#
.SYNOPSIS
    Kamico Android 发行包构建（手动触发，参数可改）。

.DESCRIPTION
    先按参数调整版本号，再按需构建发行用的 Release APK：
      arm64-v8a   主推架构，常规真机
      x86_64      模拟器与 x86 平板
      universal   三 ABI 合并（armeabi-v7a / arm64-v8a / x86_64）

    产物写入 releases/<版本>/distribution/
    构建日志写入 releases/<版本>/distribution-logs/
    调试符号写入 releases/<版本>/distribution-symbols/
    校验值写入 releases/<版本>/distribution-SHA256SUMS.txt

    按 docs/REPOSITORY.md 的发行清单，默认只出这三个 APK；
    Debug/Profile 包与 AAB 不在此脚本范围内（Debug 用 tool/build_batch.ps1）。

.PARAMETER Version
    语义版本号，例如 1.0.3。缺省沿用 pubspec.yaml 的当前值。

.PARAMETER BuildNumber
    versionCode，例如 33。缺省沿用当前值；若同时改了 Version 却没给此项，
    则在当前 versionCode 上加 1。

.PARAMETER Targets
    要构建的包，可用逗号分隔，默认 all（等价于 arm64-v8a,x86_64,universal）。

.PARAMETER SdkPath
    Android SDK 路径。缺省依次取 ANDROID_HOME、ANDROID_SDK_ROOT、
    android/local.properties 里的 sdk.dir。

.PARAMETER NoVersionWrite
    只构建，不改写 pubspec.yaml 与 lib/app_version.dart。

.PARAMETER SkipVerify
    跳过 aapt2 / apksigner 校验（不建议）。

.PARAMETER SourceArchive
    额外打包 releases/<版本>/source.zip。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build_release.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build_release.ps1 -Version 1.0.3 -BuildNumber 33

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build_release.ps1 -Targets arm64-v8a

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build_release.ps1 -Version 1.0.3 -BuildNumber 33 -SourceArchive
#>
param(
    [string]$Version = '',
    [string]$BuildNumber = '',
    [string[]]$Targets = @('all'),
    [string]$SdkPath = '',
    [switch]$NoVersionWrite,
    [switch]$SkipVerify,
    [switch]$SourceArchive
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$releaseDirectory = $PSScriptRoot
$projectDirectory = Split-Path -Parent $releaseDirectory
Set-Location -LiteralPath $projectDirectory

# 签名证书指纹，与已验收基线一致；换签名时同步改这里。
$expectedSigner = 'c9c2e03d943cfa9a1f4ea7f2386075789db7ebb9ae360b035d337594cdcf78b2'
$expectedPackage = 'app.jmpic.jm_mobile'
$expectedLabel = 'kamico'

# 发行包形态：目标名 -> Flutter target-platform 与应含 ABI
$targetTable = [ordered]@{
    'arm64-v8a' = @{ Platform = 'android-arm64'; Abis = @('arm64-v8a') }
    'x86_64'    = @{ Platform = 'android-x64'; Abis = @('x86_64') }
    'universal' = @{ Platform = 'android-arm,android-arm64,android-x64'; Abis = @('armeabi-v7a', 'arm64-v8a', 'x86_64') }
}
$defaultTargets = @('arm64-v8a', 'x86_64', 'universal')

# ---------- 1. 版本号 ----------
$manifestPath = Join-Path $projectDirectory 'pubspec.yaml'
$manifest = [System.IO.File]::ReadAllText($manifestPath)
$versionMatch = [regex]::Match($manifest, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)')
if (-not $versionMatch.Success) { throw 'pubspec.yaml 里找不到形如 version: 1.0.2+32 的版本行' }

$currentVersion = $versionMatch.Groups[1].Value
$currentBuild = $versionMatch.Groups[2].Value

if ($Version -eq '') { $Version = $currentVersion }
if ($BuildNumber -eq '') {
    if ($Version -eq $currentVersion) {
        $BuildNumber = $currentBuild
    }
    else {
        $BuildNumber = [string]([int]$currentBuild + 1)
        Write-Host "未指定 -BuildNumber，按惯例自动进位到 $BuildNumber" -ForegroundColor Yellow
    }
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "版本号格式不对：'$Version'（需要形如 1.0.3）" }
if ($BuildNumber -notmatch '^\d+$') { throw "构建号格式不对：'$BuildNumber'（需要纯数字）" }

$versionChanged = ($Version -ne $currentVersion) -or ($BuildNumber -ne $currentBuild)
if ($versionChanged) {
    if ($NoVersionWrite) {
        Write-Warning "版本改为 $Version+$BuildNumber，但已指定 -NoVersionWrite，pubspec.yaml 保持 $currentVersion+$currentBuild；此时实际产物版本仍为后者。"
        $Version = $currentVersion
        $BuildNumber = $currentBuild
        $versionChanged = $false
    }
    else {
        $newManifest = [regex]::Replace($manifest, '(?m)^version:[^\r\n]*', "version: $Version+$BuildNumber")
        [System.IO.File]::WriteAllText($manifestPath, $newManifest, $utf8NoBom)
        $appVersionPath = Join-Path $projectDirectory 'lib/app_version.dart'
        [System.IO.File]::WriteAllText($appVersionPath, "const appVersion = '$Version';", $utf8NoBom)
        Write-Host "版本：$currentVersion+$currentBuild -> $Version+$BuildNumber" -ForegroundColor Green
    }
}
else {
    Write-Host "版本：$Version+$BuildNumber（未变化）" -ForegroundColor Green
}

# ---------- 2. 目标 ----------
$requested = @()
foreach ($item in $Targets) {
    foreach ($piece in ($item -split ',')) {
        $piece = $piece.Trim()
        if ($piece -ne '') { $requested += $piece }
    }
}
if ($requested.Count -eq 0) { $requested = @('all') }
if ($requested -contains 'all') { $requested = $defaultTargets }
foreach ($name in $requested) {
    if (-not $targetTable.Contains($name)) {
        throw "未知目标 '$name'；可选：all、$($targetTable.Keys -join '、')"
    }
}
$requested = @($requested | Select-Object -Unique)

# ---------- 3. 目录与工具 ----------
$versionDirectory = Join-Path $releaseDirectory $Version
$distributionDirectory = Join-Path $versionDirectory 'distribution'
$logDirectory = Join-Path $versionDirectory 'distribution-logs'
$symbolsDirectory = Join-Path $versionDirectory 'distribution-symbols'
foreach ($path in @($versionDirectory, $distributionDirectory, $logDirectory, $symbolsDirectory)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}

$flutterExecutable = (Get-Command flutter -ErrorAction Stop).Source
Write-Host "构建目标：$($requested -join ', ')" -ForegroundColor Cyan
Write-Host "输出目录：$distributionDirectory" -ForegroundColor Cyan

# ---------- 4. 构建 ----------
$built = @()
foreach ($target in $requested) {
    $spec = $targetTable[$target]
    $destination = Join-Path $distributionDirectory "Kamico-$Version-android-$target.apk"
    $logPath = Join-Path $logDirectory "build-$target.log"

    $buildArguments = @(
        'build', 'apk', '--release', '--no-pub',
        "--target-platform=$($spec.Platform)",
        "--split-debug-info=$symbolsDirectory",
        '-Pdisable-abi-filtering=true'
    )
    if ($target -ne 'universal') { $buildArguments += "-PjmAbi=$target" }

    Write-Host ""
    Write-Host ">>> 构建 $target ..." -ForegroundColor Cyan
    # flutter.bat 会把 storage-mirror 警告写到 stderr，PowerShell 5.1 在
    # 'Stop' 下会把重定向的原生 stderr 当终止错误，这里临时放宽后看真实退出码。
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $flutterExecutable @buildArguments *> $logPath
        $buildExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($buildExitCode -ne 0) {
        Get-Content -LiteralPath $logPath -Tail 60
        throw "构建失败：$target（日志：$logPath）"
    }

    $produced = Join-Path $projectDirectory 'build/app/outputs/flutter-apk/app-release.apk'
    if (-not (Test-Path -LiteralPath $produced)) { throw "找不到产物：$produced" }
    Copy-Item -LiteralPath $produced -Destination $destination -Force
    $sizeMb = [math]::Round((Get-Item -LiteralPath $destination).Length / 1MB, 2)
    Write-Host "<<< 完成 $target（$sizeMb MB）" -ForegroundColor Green
    $built += @{ Target = $target; Path = $destination }
}

# ---------- 5. 校验 ----------
# 直接读 zip 中央目录，取 lib/<abi>/libapp.so 的 abi 集合。
function Get-ApkAppAbis {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $abis = @()
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '^lib/([^/]+)/libapp\.so$') { $abis += $Matches[1] }
        }
        if ($abis.Count -eq 0) { throw "APK 里找不到 lib/<abi>/libapp.so：$Path" }
        return @($abis | Sort-Object)
    }
    finally { $archive.Dispose() }
}

$records = @()
if ($SkipVerify) {
    Write-Warning '已跳过校验'
}
else {
    if ($SdkPath -eq '') {
        if ($env:ANDROID_HOME) { $SdkPath = $env:ANDROID_HOME }
        elseif ($env:ANDROID_SDK_ROOT) { $SdkPath = $env:ANDROID_SDK_ROOT }
        else {
            $localProperties = Join-Path $projectDirectory 'android/local.properties'
            if (Test-Path -LiteralPath $localProperties) {
                $line = Select-String -LiteralPath $localProperties -Pattern '^\s*sdk\.dir\s*=\s*(.+)$' | Select-Object -First 1
                if ($line) { $SdkPath = $line.Matches[0].Groups[1].Value.Trim().Replace('\\', '\') }
            }
        }
    }
    if (-not $SdkPath -or -not (Test-Path -LiteralPath $SdkPath)) {
        throw "找不到 Android SDK：请用 -SdkPath 指定，或设置 ANDROID_HOME / android/local.properties 的 sdk.dir"
    }

    $buildTools = Get-ChildItem -LiteralPath (Join-Path $SdkPath 'build-tools') -Directory |
        Sort-Object { [int](($_.Name -split '\.')[0]) }, { [int](($_.Name -split '\.')[1]) } |
        Select-Object -Last 1
    if (-not $buildTools) { throw "build-tools 目录为空：$SdkPath\build-tools" }
    $aapt2 = Join-Path $buildTools.FullName 'aapt2.exe'
    $apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
    foreach ($tool in @($aapt2, $apksigner)) {
        if (-not (Test-Path -LiteralPath $tool)) { throw "缺少工具：$tool" }
    }
    Write-Host ""
    Write-Host ">>> 校验（build-tools $($buildTools.Name)）..." -ForegroundColor Cyan

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $sdkLevels = @{}
        foreach ($item in $built) {
            $path = $item.Path
            $name = Split-Path -Leaf $path
            $badging = (& $aapt2 'dump' 'badging' $path) -join "`n"

            $expectedIdentity = "name='$expectedPackage' versionCode='$BuildNumber' versionName='$Version'"
            if ($badging -notlike "*$expectedIdentity*") {
                throw "$name 的包名/版本不符：期望 $expectedIdentity"
            }
            if ($badging -notlike "*application-label:'$expectedLabel'*") {
                throw "$name 的显示名不是 '$expectedLabel'"
            }
            if ($badging -like '*application-debuggable*') {
                throw "$name 仍是 debuggable，不是发行包"
            }

            $minSdk = [regex]::Match($badging, "(?m)^(?:minSdkVersion|sdkVersion):'(\d+)'").Groups[1].Value
            $targetSdk = [regex]::Match($badging, "(?m)^targetSdkVersion:'(\d+)'").Groups[1].Value
            if (-not $minSdk -or -not $targetSdk) { throw "$name 读不出 minSdk/targetSdk" }
            $sdkLevels[$name] = "$minSdk/$targetSdk"

            # native-code 行会被插件的 x86 库带偏（universal 里 x86 只有插件库、
            # 没有 Flutter 引擎库），因此按 lib/<abi>/libapp.so 判定实际 ABI。
            $actualAbis = @(Get-ApkAppAbis -Path $path)
            $expectedAbis = @($targetTable[$item.Target].Abis | Sort-Object)
            if (($actualAbis -join ',') -ne ($expectedAbis -join ',')) {
                throw "$name 的 ABI 不符：实际 $($actualAbis -join ',')，期望 $($expectedAbis -join ',')"
            }

            $signing = (& $apksigner 'verify' '--print-certs' $path) -join "`n"
            $signer = [regex]::Match($signing, 'Signer #1 certificate SHA-256 digest:\s*(\w+)').Groups[1].Value
            if ($signer -ne $expectedSigner) {
                throw "$name 的签名不符：实际 $signer，期望 $expectedSigner"
            }

            $sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            $bytes = (Get-Item -LiteralPath $path).Length
            $records += [pscustomobject]@{
                file = $name
                target = $item.Target
                version = "$Version+$BuildNumber"
                bytes = $bytes
                abis = $actualAbis
                minSdk = [int]$minSdk
                targetSdk = [int]$targetSdk
                certificateSha256 = $signer
                sha256 = $sha256
            }
            Write-Host "    OK  $name（ABI $($actualAbis -join ',')）" -ForegroundColor Green
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $distinctSdk = @($sdkLevels.Values | Select-Object -Unique)
    if ($distinctSdk.Count -gt 1) { throw "各包 minSdk/targetSdk 不一致：$($distinctSdk -join ' vs ')" }
    Write-Host "    SDK: $($distinctSdk[0])（minSdk/targetSdk）" -ForegroundColor DarkGray

    $verificationPath = Join-Path $versionDirectory 'distribution-verification.json'
    ConvertTo-Json -InputObject @($records) -Depth 5 |
        ForEach-Object { [System.IO.File]::WriteAllText($verificationPath, $_ + [Environment]::NewLine, $utf8NoBom) }

    $sumsPath = Join-Path $versionDirectory 'distribution-SHA256SUMS.txt'
    $sumLines = $records | ForEach-Object { "$($_.sha256)  $($_.file)" }
    [System.IO.File]::WriteAllText($sumsPath, ($sumLines -join [Environment]::NewLine) + [Environment]::NewLine, $utf8NoBom)
    Write-Host "    记录：$verificationPath" -ForegroundColor DarkGray
    Write-Host "    校验值：$sumsPath" -ForegroundColor DarkGray
}

# ---------- 6. 源码包（可选） ----------
if ($SourceArchive) {
    $archivePath = Join-Path $versionDirectory 'source.zip'
    if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
    # 与 tool/build_batch.ps1 保持同一份白名单；不直接打整个工程，
    # 否则会把 .gradle / ephemeral 缓存和 docs/ 一并打进去。
    $includeList = @(
        'lib', 'test', 'tool', 'assets', 'artwork', 'android', 'windows',
        'pubspec.yaml', 'pubspec.lock', 'README.md', 'LICENSE',
        'THIRD_PARTY_NOTICES.md', 'third_party'
    )
    $excludeList = @(
        '--exclude=android/.gradle', '--exclude=android/.kotlin',
        '--exclude=android/app/.cxx', '--exclude=android/app/build',
        '--exclude=android/local.properties', '--exclude=android/key.properties',
        '--exclude=*.jks', '--exclude=*.keystore',
        '--exclude=tool/baseline15', '--exclude=tool/__pycache__'
    )
    # -a 只有 Windows 自带 bsdtar 支持；PATH 里的 MSYS tar 会报
    # 'Cannot connect to D: resolve failed'。
    & "$env:SystemRoot\System32\tar.exe" -a -cf $archivePath @excludeList @includeList
    if ($LASTEXITCODE -ne 0) { throw "打包 source.zip 失败（tar 退出码 $LASTEXITCODE）" }
    $archiveMb = [math]::Round((Get-Item -LiteralPath $archivePath).Length / 1MB, 2)
    Write-Host "源码包：$archivePath（$archiveMb MB）" -ForegroundColor Green
}

# ---------- 7. 汇总 ----------
Write-Host ""
Write-Host "==== 完成：Kamico $Version+$BuildNumber ====" -ForegroundColor Cyan
foreach ($item in $built) {
    $sizeMb = [math]::Round((Get-Item -LiteralPath $item.Path).Length / 1MB, 2)
    $sha = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host ("{0,-34} {1,8} MB  {2}" -f (Split-Path -Leaf $item.Path), $sizeMb, $sha)
}
Write-Host ""
Write-Host "产物目录：$distributionDirectory"
Write-Host "按 docs/REPOSITORY.md 的发行清单，只上传上面这三个 APK。"
if ($versionChanged) {
    Write-Host "注意：本次已改写 pubspec.yaml 与 lib/app_version.dart，记得连同产物一起提交。" -ForegroundColor Yellow
}
