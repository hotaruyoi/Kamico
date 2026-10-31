# Kamico Android

JMComic / PicACG 双源 Flutter 漫画客户端，当前版本 **1.0.3+37**。

项目功能、阅读体验、安装包选择及使用说明见仓库根目录的 [README](../README.md)。发行文件位于 [GitHub Releases](https://github.com/hotaruyoi/Kamico/releases)。

## 常用命令

在本目录中执行；已有依赖时无需重新获取：

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub --target-platform=android-arm64 -PjmAbi=arm64-v8a -Pdisable-abi-filtering=true
```

Windows 批量打包（Release + Debug 双包）：

```powershell
.\tool\build_batch.ps1 -Version 1.0.3 -BuildNumber 37 -Mode both
```

发行包（ARM64、x86_64、Universal 三个 Release APK，手动触发、参数可调）用 `releases\build_release.ps1`。该脚本与 `releases/` 下的产物、日志一样不入仓库，只存在于本地：克隆仓库后该目录是空的，需要从本机备份取回（仓库不携带该脚本，也不携带 `docs/`）。

脚本按参数改写 `pubspec.yaml` 与 `lib/app_version.dart`，构建 `releases/<版本>/distribution/` 下的三个发行 APK，并用 `aapt2` / `apksigner` 校验包名、版本、标签、ABI、minSdk/targetSdk 与签名，输出 `distribution-verification.json` 与 `distribution-SHA256SUMS.txt`。`-NoVersionWrite` 只构建不改版本，`-SkipVerify` 跳过校验；构建日志、调试符号与校验记录留在待发布目录之外。

Release 包名为 `app.jmpic.jm_mobile`；Debug/Profile 使用独立的 `app.jmpic.jm_mobile.debug`，供本地调试，可与正式版同时安装。

本地依赖缓存、构建输出和签名密钥不纳入仓库。来源与许可见 [第三方声明](THIRD_PARTY_NOTICES.md)。
