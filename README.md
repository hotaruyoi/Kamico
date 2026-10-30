<div align="center">
  <img src="Kamico_android/artwork/launcher-foreground.png" width="120" alt="Kamico 图标" />
  <h1>Kamico</h1>
  <p>发现、收藏、阅读与离线下载，一处完成</p>
  <p><a href="https://github.com/hotaruyoi/Kamico/releases/latest">下载发行版</a> · <a href="https://github.com/hotaruyoi/Kamico/issues">反馈问题</a></p>
</div>

Kamico 是一款支持 **JMComic / PicACG 双源**的 Android 漫画客户端。统一的操作方式、按来源整理的书架，以及可按习惯调整的阅读器，让找书、继续阅读和离线查看衔接在一起。

当前版本 **1.0.2**，支持 **Android 7.0 及以上**系统。

## 功能与使用体验

### 两个来源，一套操作习惯

在发现页或“我的”右上角点击即可切换来源，标题会标明当前来源。两个账号独立登录，搜索记录与筛选条件分别保存；切换后仍使用相同的发现、详情、书架与阅读操作。

本地收藏、历史与下载在同一个入口中按来源分组。打开其他来源的作品时，应用自动使用作品对应的来源，返回后保留原先选择的全局来源。

### 从发现到阅读

通过首页推荐、分类、排行和搜索寻找作品，用排序、时间范围与分页缩小结果。发现页快捷入口支持拖动排序，常用入口可以放在前面。

详情页集中展示封面、作者、简介、标签、点赞数与章节目录。简介和目录按需展开，章节支持搜索及不同排列方式，也可以直接选章下载。

### 按自己的习惯阅读

- **竖向连续阅读**：向上滑动接着阅读，适合连贯浏览整章内容。
- **左右翻页**：可选择向左或向右滑动进入下一页，适应不同翻阅习惯。
- **随时调整进度**：支持跳页、缩放与进度恢复，也可开启自动阅读和预加载。
- **菜单覆盖显示**：点击画面中央呼出或收起工具栏，保持漫画画面与当前位置稳定。

阅读设置在两个来源间共用。回到历史或书架后，可以继续上次未读完的位置。

### 书架与历史，方便整理和继续阅读

本地收藏支持分组、筛选与批量操作；历史记录保留阅读位置，便于找回最近看过的作品。JMComic 与 PicACG 条目分区显示，两个来源的内容都有明确归属。

云端收藏与云端历史按来源支持的能力提供；PicACG 当前没有已接入的云端历史接口，本地历史仍可使用。

### 下载后离线查看，也能导出 PDF

可以选择章节或按编号批量加入下载队列，支持暂停、继续、取消和失败重试。切换来源不会暂停原来源的队列；应用重新打开后可恢复未完成的任务。

下载内容集中在本地书库中，支持搜索、排序、离线阅读及批量管理，也可导入已有的本地目录。PDF 导出到系统下载目录，便于使用其他阅读器查看；清理应用内缓存不会删除已导出的公共 PDF。

### 外观随设备与偏好调整

采用 Material 3 界面，提供跟随系统、浅色和深色主题，以及主题色、字体、字号与卡片密度设置。支持简体中文、繁体中文和英文，可根据屏幕大小调整内容布局。

## 下载与安装

前往 [Releases](https://github.com/hotaruyoi/Kamico/releases) 下载适合设备的 APK。后续发行仅提供以下三个版本：

| 版本 | 适用情况 |
| --- | --- |
| **ARM64** · `android-arm64-v8a.apk` | 大多数现代 Android 手机，优先选择 |
| **x86_64** · `android-x86_64.apk` | AMD64 / Intel 64 位 Android 设备与模拟器 |
| **Universal** · `android-universal.apk` | 覆盖常用 Android 架构；不确定设备架构时选择，体积较大 |

安装其中一个即可。首次安装按 Android 系统提示允许安装应用，后续可用相同签名的安装包覆盖升级。

## 开始使用

1. 在发现页选择来源，按需登录对应账号。
2. 浏览分类或搜索作品，在详情中选择章节开始阅读。
3. 将喜欢的作品加入书架，通过历史记录继续阅读。
4. 需要离线查看时选择章节下载；下载期间建议保持应用在前台。

导出的 PDF 默认位于 `Downloads/kamico/JM/` 或 `Downloads/kamico/PIC/`，也可以自行选择保存目录。不同来源的可用功能及网络连接情况以相应服务为准。

## 开源与反馈

客户端源码位于 [`Kamico_android/`](Kamico_android/)。遇到问题或有改进建议，欢迎在 [Issues](https://github.com/hotaruyoi/Kamico/issues) 中反馈，附上应用版本、设备系统及复现步骤有助于定位。

## 许可与致谢

本项目按 [GNU LGPL v3](Kamico_android/LICENSE) 分发。感谢 [JMComic-qt](https://github.com/tonquer/JMComic-qt)、[picacg-qt](https://github.com/tonquer/picacg-qt) 和 [JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python) 提供的参考，完整来源与许可见 [第三方声明](Kamico_android/THIRD_PARTY_NOTICES.md)。
