# 真机调试与验收

用户使用 Release 验收，代理使用 Debug 调试；每轮交付同时构建和安装两个版本。Release 保持既有包名与签名以覆盖升级，Debug/Profile 共享独立调试身份。

| 用途 | 显示名称 | Android 包名 | 默认公共 PDF 目录 |
| --- | --- | --- | --- |
| 用户验收 | kamico | app.jmpic.jm_mobile | Downloads/kamico |
| 代理调试 | kamico Debug | app.jmpic.jm_mobile.debug | Downloads/kamico-debug |

账号、偏好、本地库、缓存、私有下载和安全凭据由 Android 按包名隔离；调试版初次安装不继承正式版登录。文件共享 Provider 使用应用自己的包名，不与另一个版本冲突。用户显式选择的外部导出目录仍按其选择处理。

## 运行与构建

工程目录中执行 `flutter run --debug --no-pub -d <设备序列号>`，工具会解析 Debug 包名；已有会话中 `r` 热重载。Profile 也安装到调试身份，不覆盖用户验收包。

打包脚本默认同时构建 Release 和 Debug，输出到同一个版本目录；`-Mode debug` 可只更新调试包，`-Mode release -AnalyzeSize` 单独做体积分析。生成的新调试包应定期安装，避免结束进程后丢失仅热重载的改动。

ADB 启动组件使用完整 Activity 名称：

```text
Release: app.jmpic.jm_mobile/app.jmpic.jm_mobile.MainActivity
Debug:   app.jmpic.jm_mobile.debug/app.jmpic.jm_mobile.MainActivity
```

先确认目标包名和进程，再用 ADB 输入、可访问性树、当前进程日志及 Dart VM 状态验证操作结果。只有视觉布局无法由这些数据判断时截图；同一状态不重复截图。真实账号写操作仍由用户发起，自动回归使用合成数据。

## 合成性能与原生阅读探针

`tool/profile_scenarios.dart` 是显式选择的独立入口，包含 96 本本地封面样本、合成离线页和内存偏好。使用 `flutter build apk --profile --no-pub --target=tool/profile_scenarios.dart` 构建时继续带上既有 ARM64 参数；默认产品入口仍为 `lib/main.dart`。Profile / Debug 共用 `.debug` 身份，合成入口不读取该身份已有的账号与进度。

`tool/measure_device_profile.py --help` 说明采集参数；输入 `flutter run --profile --no-dds` 的本地日志，由工具读取 VM 地址，输出 UI/栅格 FrameTiming、刷新率预算、帧数与内存。`tool/probe_reader_menu.py --help` 则检查页面中途菜单显隐时的实际窗口、视口、图片坐标及元素身份，可用于 Debug 和 Profile。VM 认证地址只留在忽略的本地日志中，不写入公开报告。

完成采样后重新安装本轮标准 `app-arm64-debug.apk`，使调试应用恢复产品入口；同时核对 Release / Debug 的版本、构建号和身份。报告明确区分合成 Profile 帧耗时、本机查询基准与正式版真实网络体验，避免把间歇操作的帧数换算成持续 FPS。
