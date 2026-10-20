# Kamico Android

JM / PicACG 双源 Flutter 漫画客户端，当前版本 **1.0.1+29**。

项目介绍、安装包选择、使用说明、源码构建及许可信息见仓库根目录的 [README](../README.md)。发行文件位于 [GitHub Releases](https://github.com/hotaruyoi/Kamico/releases)。

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

工具读取 `pubspec.yaml` 中的版本，生成 ARM64、ARMv7、x86_64、通用 APK 和 AAB，输出到本地 `releases/<版本>/distribution/`。Release 包名为 `app.jmpic.jm_mobile`；Debug/Profile 使用独立的 `app.jmpic.jm_mobile.debug`，可与正式版同时安装。

本地依赖缓存、构建输出和签名密钥不纳入仓库。来源与许可见 [第三方声明](THIRD_PARTY_NOTICES.md)。
