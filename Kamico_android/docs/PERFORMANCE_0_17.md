# kamico 0.17.0 性能与体积优化

2026-10-19。用户反馈 0.16.0 在 vivo X300 Pro、智能刷新率最高 120Hz、默认字体且无下载时，首页和详情等多页上下滑动明显掉帧。用户指出此前 Debug 包没有同样明显的卡顿，因此本轮实施代码优化，并实际测量 Release 体积，不能仅用 Debug 模式解释反馈。

## 已确认的代码开销与修改

### 1. 滚动过程中重复解析历史、收藏与章节进度

`ComicCard`、书架列表和目录行读取 `LocalStore` 时，原 getter 会反复解析整份 JSON、转换全部模型；目录查询还可能回退扫描历史。对 1500 条记录，100 次相同的卡片/章节查询可以稳定复现这项开销。

- 历史、收藏和章节进度改为按底层偏好字符串版本失效的只读快照；底层数据变化时更新，不在每张卡片构建时重复解析。
- 为最近阅读和章节进度建立索引，卡片“读过”及详情最近阅读使用按编号查询。
- 收藏写入时复制需修改的数据；覆盖测试保证移动、删除、保存进度及直接更新偏好后不会读到陈旧状态。
- 首次读取仍有一次解析开销，缓存模型会增加常驻内存；未改变原有持久化格式，也未删除用户历史。

### 2. 阅读进度导致应用级重建

原 `JmApp` 监听整个会话，每次进度保存或任务状态通知都会重新构造 MaterialApp、主题及字号缩放对象。

- 外观通知与普通会话通知分开；主题只在外观改变时重建。
- 登录失效提示保留独立监听，复用 Navigator 子树；隐藏在阅读/详情路由下的主页不因进度通知主动刷新，返回时依赖路由状态更新。
- 字号缩放器提供值相等判断，避免相同缩放值触发不必要的继承数据变化。
- 测试确认：保存阅读进度时 MaterialApp 实例保持不变，改变主题色后仍正常更新。

### 3. 封面和详情布局

- 封面不再统一请求 400px 解码宽度，根据实际布局宽度 × 像素密度选取 64px 档位，保留原 400px 上限。例如 48dp × 2 的封面使用 128px，而非 400px；减轻小卡片解码和纹理压力。
- 简介是否超过四行的测量结果按文本、宽度、字体、文字方向和缩放缓存，输入不变时不重复 TextPainter 测量。
- 保留现有 Sliver 懒构建、折叠、评论、PDF 和三模式阅读。用户要求先记录的目录工具栏视觉改动本轮未实施。

## 可复现基准与验证边界

命令：

```powershell
flutter test test/performance_regression_test.dart --no-pub
flutter test test/perf/local_store_benchmark.dart --no-pub
flutter test --no-pub --dart-define=CAPTURE_UI=true
flutter analyze --no-pub
```

修改前先运行测试，确认重复解析快照及进度触发 MaterialApp 重建的断言失败；小封面解码尺寸断言也先失败。修改后这些回归及完整 88 项测试通过，静态检查 No issues found。

基准预热一次，在本机 Windows Flutter 测试运行器中对 1500 条记录重复执行 100 次卡片状态/章节查询，测量五次，记录中位值：

| 项目 | 修改前 | 修改后 |
|---|---:|---:|
| 同一查询循环中位耗时 | 516070μs | 597μs |
| 48dp、2× 密度封面请求解码宽度 | 400px | 128px |
| 进度保存是否重构 MaterialApp | 是 | 否 |

日志：`releases/0.17.0/performance-before.log`、`releases/0.17.0/performance-after.log`、`releases/0.17.0/cover-before.log`、`releases/0.17.0/tests.log`、`releases/0.17.0/analyze.log`。

这些开销通过实际代码调用路径复现，不是真机整帧测量。重复解析和过宽的通知范围在 0.15.0 中也存在，不能据此宣称已定位 0.16.0 独有回归；历史数据增长等因素仍需真机记录验证。本轮没有手机连接，没有测得 X300 Pro 的 FPS、p95/p99 帧耗时或内存峰值，不能承诺已经消除所有掉帧。

## 包体积实测

| 安装包 | 字节数 | MiB |
|---|---:|---:|
| 0.16.0 ARM64 Debug | 92311683 | 88.04 |
| 0.17.0 ARM64 Release（体积分析构建） | 22452162 | 21.41 |
| 0.17.0 ARM64 Release（最终符号分离构建） | 21075906 | 20.10 |
| 0.17.0 ARM64 Debug（同代码对照） | 92317167 | 88.04 |

最终 Release 相对旧 Debug 缩小约 77.17%。同代码 Debug 仍较大，说明大小主要由构建载荷决定；不是 PDF 下载把漫画内容或设备字体打进安装包。

0.16.0 Debug 主要组成：Flutter 引擎约 35.84 MiB、kernel 调试代码约 26.69 MiB、Vulkan 校验库约 14.53 MiB、isolate 快照约 4.04 MiB。0.15.0 与它的体积接近。

Release 使用单 ARM64、Dart AOT、默认开启的 R8/资源裁剪、图标裁剪；分离 Dart 调试符号并保留包外符号及 R8 映射。图标字体由 1645184 字节裁剪至 12996 字节。最终 APK 无 kernel_blob、isolate_snapshot_data 和 Vulkan 校验库，主要剩余 Flutter 引擎约 11.04 MiB、应用及依赖 AOT 库约 7.75 MiB、classes.dex 约 0.60 MiB。

`tool/build_batch.ps1` 默认改为 Release；`-Mode debug` 用于对照，`-AnalyzeSize` 单独生成分析构建。符号分离与 analyze-size 不可同时使用，脚本已分别处理。体积分析 JSON 在版本目录 `size-analysis/`，最终符号和混淆映射在 `symbols/`。本轮没有启用 Dart 名称混淆。

## 安装包与验收

- 最终文件：`releases/0.17.0/app-arm64-release.apk`；Debug 对照：同目录 `app-arm64-debug.apk`。
- 名称 kamico；versionName 0.17.0，versionCode 17；包名 `app.jmpic.jm_mobile`，仅 arm64-v8a；minSdk 24、targetSdk 36。
- Release APK 非 debuggable，v2 签名通过，与旧版证书一致，可覆盖升级；当前仍沿用开发签名，尚未切换正式发行密钥。
- Release SHA256：`d1b0808c4098577173c1e0964fd8b705d2dfce9c491eb649baa909cd0d2cac58`。
- Debug SHA256：`17bd38af7a340faee6dec38dc4b1e35014ed7f8c17e60368fde1bdb1f7ac1027`。
- 建议先验收 Release 的首页、详情展开目录和连续阅读，再用本版 Debug 对照旧版 Debug；保持字体、数据、下载状态及滑动路线一致。如仍掉帧，按 NEXT_ITERATION 的 Profile 方案采集真机长帧后继续定位。

参考：[Flutter 体积测量](https://docs.flutter.dev/perf/app-size)、[AOT 与体积分析](https://docs.flutter.dev/tools/devtools/app-size)、[性能最佳实践](https://docs.flutter.dev/perf/best-practices)。
