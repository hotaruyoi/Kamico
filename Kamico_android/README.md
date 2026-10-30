# Kamico Android

JMComic / PicACG 双源 Flutter 漫画客户端，当前版本 **1.0.2+32**。

项目功能、阅读体验、安装包选择及使用说明见仓库根目录的 [README](../README.md)。发行文件位于 [GitHub Releases](https://github.com/hotaruyoi/Kamico/releases)。

## 常用命令

在本目录中执行；已有依赖时无需重新获取：

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub --target-platform=android-arm64 -PjmAbi=arm64-v8a -Pdisable-abi-filtering=true
```

Windows 批量打包：

```powershell
.\tool\build_distribution.ps1
```

工具读取 `pubspec.yaml` 中的版本，仅生成 ARM64、x86_64 和 Universal 三个 Release APK，输出到本地 `releases/<版本>/distribution/`。构建日志及校验记录保留在待发布目录之外。

Release 包名为 `app.jmpic.jm_mobile`；Debug/Profile 使用独立的 `app.jmpic.jm_mobile.debug`，供本地调试，可与正式版同时安装。

本地依赖缓存、构建输出和签名密钥不纳入仓库。来源与许可见 [第三方声明](THIRD_PARTY_NOTICES.md)。
