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
