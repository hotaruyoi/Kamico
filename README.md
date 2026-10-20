<div align="center">
  <img src="Kamico_android/artwork/launcher-foreground.png" width="120" alt="Kamico 图标" />
  <h1>Kamico</h1>
  <p>基于 Flutter 的 JM / PicACG 双源 Android 漫画客户端</p>
  <p><a href="https://github.com/hotaruyoi/Kamico/releases/latest">下载发行版</a> · <a href="https://github.com/hotaruyoi/Kamico/issues">反馈问题</a></p>
</div>

Kamico 将发现、搜索、书架、历史、阅读与离线下载整合到统一的 Material 3 界面中。当前版本为 **1.0.1**，支持 Android 7.0 及以上系统。

## 功能

- **双源切换**：在发现页或“我的”右上角点击切换 JM / PicACG，两个账号独立登录，搜索记录与筛选条件按来源保存。
- **发现与搜索**：首页推荐、分类、排行、排序筛选和分页；入口按数据源能力显示，支持拖动调整发现页快捷入口顺序。
- **书架与历史**：本地收藏、阅读进度和离线内容按 JM / PIC 分组；保留云端收藏与来源支持的云端历史。
- **阅读体验**：竖向连续阅读、向左或向右翻页，支持缩放、进度恢复、跳页、自动阅读和预加载。
- **离线下载**：章节下载、队列暂停与恢复、本地目录导入、离线阅读及 PDF 导出。
- **外观设置**：系统 / 浅色 / 深色主题、主题色、字体与字号、响应式卡片布局，提供简体中文、繁体中文和英文。

## 下载与安装

前往 [Releases](https://github.com/hotaruyoi/Kamico/releases) 下载。版本页中的文件按以下规则命名：

| 文件后缀 | 用途 |
| --- | --- |
| `android-arm64-v8a.apk` | 大多数现代 Android 手机，优先选择 |
| `android-armeabi-v7a.apk` | 仍支持 32 位应用的旧 ARM 设备 |
| `android-x86_64.apk` | AMD64 / Intel 64 位 Android 设备与模拟器 |
| `android-universal.apk` | 包含以上三种架构，体积较大；不确定架构时使用 |
| `android.aab` | Android App Bundle，供分发平台处理，不能直接点击安装 |
| `source.zip` | 对应源码快照 |
| `SHA256SUMS.txt` | 文件完整性校验值 |

选择一种 APK 安装即可。首次安装时按系统提示允许当前下载工具安装应用；后续使用相同签名的 APK 覆盖升级。`x86_64` APK 运行于 Android，并非 Windows、Linux 或 macOS 桌面程序。

## 使用说明

1. 选择数据源后登录对应账号；切源保留另一个账号的登录状态。
2. 本地收藏、历史和下载按来源分组，从本地库打开作品时自动使用作品自身的数据源。
3. 新增 PDF 默认保存在系统 `Downloads/kamico/JM/` 或 `Downloads/kamico/PIC/` 下；删除应用内缓存不会删除已导出的公共 PDF。
4. 下载期间需保持应用在前台；中断任务可在下次打开应用后恢复。

不同来源的能力有所区别，例如 PicACG 当前没有已接入的云端历史接口。上游服务的网络状态、登录要求及内容可用性由相应服务决定。

## 从源码构建

客户端位于 [`Kamico_android/`](Kamico_android/)。当前工程使用 Flutter 3.44.8 / Dart 3.12.2，Android SDK 36 和 JDK 21；依赖版本由 `pubspec.lock` 固定。

在新环境完成 Flutter / Android 工具链配置后执行：

```sh
cd Kamico_android
flutter pub get
flutter analyze
flutter test
```

已有依赖缓存时可使用 `--no-pub`，无需清理缓存或升级依赖。构建示例：

```sh
# ARM64 APK
flutter build apk --release --no-pub --target-platform=android-arm64 -PjmAbi=arm64-v8a -Pdisable-abi-filtering=true

# ARMv7、ARM64、x86_64 通用 APK
flutter build apk --release --no-pub --target-platform=android-arm,android-arm64,android-x64 -Pdisable-abi-filtering=true

# Android App Bundle
flutter build appbundle --release --no-pub --target-platform=android-arm,android-arm64,android-x64
```

Windows 可使用 [`build_distribution.ps1`](Kamico_android/tool/build_distribution.ps1) 批量准备发行文件。当前 Android 工程沿用既有开发签名；自行分发时请使用自己的签名配置并妥善保管密钥。仓库保留 Windows runner，当前发行目标为 Android。

## 目录

```text
Kamico_android/
  lib/domain/     模型与来源标识
  lib/data/       API、存储、图片和下载
  lib/ui/         界面与阅读器
  android/        Android 原生桥接与打包配置
  assets/        本地化资源
  artwork/       图标源资源
  test/          自动化回归
  tool/          构建及验证工具
  third_party/   第三方许可
```

## 许可与致谢

本项目按 [GNU LGPL v3](Kamico_android/LICENSE) 分发，并保留其引用的 [GNU GPL v3 正文](Kamico_android/third_party/GPL-3.0.txt)。JM 与 PicACG 协议适配参考了 [tonquer/JMComic-qt](https://github.com/tonquer/JMComic-qt)、[tonquer/picacg-qt](https://github.com/tonquer/picacg-qt)，部分协议实现参考 [hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python)。

完整来源、修改说明与第三方许可见 [THIRD_PARTY_NOTICES.md](Kamico_android/THIRD_PARTY_NOTICES.md)。发行包不包含 Python / Qt 运行时。
