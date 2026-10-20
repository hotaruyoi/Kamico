# 0.18.1 双版本交付

本版固化用户已确认的 [发现页滑动修复](DISCOVERY_SCROLL_FIX.md)，并启用 [Release／Debug 并存](DEBUGGING.md)。版本号 0.18.1+19，原始 0.18.0 交付保持不变。

- 正式版名称 kamico，继续使用原包名和签名，供用户验收。
- 调试版名称 kamico Debug，独立 `.debug` 包名；账号、偏好、私有数据及默认公共 PDF 目录分别管理。Profile 使用同一调试身份。
- Flutter 运行时标题和版本信息区分构建类型，文件共享 Provider 随包名生成，Activity 使用明确类名。
- 打包脚本默认构建两个 APK，仍支持单独构建及 Release 体积分析，源码快照只归档一次。
- 静态检查无问题，92 项回归通过，见 [验证日志](verification-0.18.1.log)。构建和安装验证继续追加在该日志。

本轮使用既有缓存和依赖；没有复制账号凭据、删除应用数据或改动手机 VPN 配置。

## 安装验证

- Release 构建 86.0 秒，APK 20.04 MiB；Debug 构建 19.6 秒，APK 88.05 MiB。
- AAPT 检查：两个包均为 0.18.1+19；名称、包名及 `.files` Provider authority 各自正确，只有 Debug 带调试标记。
- 两个 APK 均经 ADB 安装成功，分别冷启动成功，并同时存在运行进程。抽查各进程启动日志，无 FATAL、未处理异常或 E/flutter 匹配。
- 正式包保留 `/data/user/0/app.jmpic.jm_mobile` 和原首次安装时间；调试包使用 `/data/user/0/app.jmpic.jm_mobile.debug`，没有复用或复制原数据。
- 当前前台为正式版。未截图；原始 0.18.0 安装包与源码快照未变。
