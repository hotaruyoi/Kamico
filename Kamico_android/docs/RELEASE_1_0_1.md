# kamico 1.0.1

版本 **1.0.1+29**，日期 2026-10-20。本轮按用户对 1.0 的反馈修订，沿用 `feature+1.0.0`。用户于 2026-10-20 明确确认“验收通过”，验收产物对应源码提交 `77afa52`，并授权合并 `main`、推送至 [hotaruyoi/Kamico](https://github.com/hotaruyoi/Kamico)。本次验收记录仅更新维护文档，双 APK 的内容与校验值保持不变。

## 界面与图标

- 下载页本地书库改用 `LibrarySelectionToggle`：选择按钮常驻，再次点击关闭操作条并清空勾选，底部“完成选择”仍保留。继续复用透明外围的浮动操作条，列表与封面元素保持稳定。
- 发现页标题为粗体 `Kamico · JM` / `Kamico · Pic`，随当前来源更新；窄屏采用单行省略，保留标题栏切源按钮和其他页面标题。
- 用户提供的粉色 K 与少女头像通过内置 image_gen 去除外层底板，保留主体；512px 透明源放在 `artwork/launcher-foreground.png`，不声明为 Flutter 运行资产。Android 提供五档传统图标与中央安全区域内的自适应前景，Windows 同步多尺寸 ICO。复现工具和完整提示词见 [artwork/README.md](../artwork/README.md)。Android 图标资源合计 227,068 字节，原始约 1.7MB 大图不打包。
- 保留双源数据隔离、离线兼容、包名、签名、阅读三模式与既有设置；不新增运行依赖。

## Android 阅读菜单位移

真机中途阅读时，菜单显隐触发绘图窗口在 2400px / 2322px 高度间切换，差值 78px 与挖孔/状态栏区域一致。Flutter 层的图片元素与滚动偏移未变，因此原有仅改变 MediaQuery 安全区的组件回归无法覆盖此问题。

Android 窗口现在固定挖孔布局策略（API 30 起 ALWAYS，API 28–29 使用 SHORT_EDGES），系统栏通过 WindowInsetsControllerCompat 覆盖显隐；阅读控件仍遵循安全区，内容不因系统栏显隐重新分配窗口。其他平台保留原 SystemChrome 回退。依据见 [Android 挖孔布局](https://developer.android.com/develop/ui/views/layout/display-cutout)与[沉浸式系统栏](https://developer.android.com/develop/ui/views/layout/immersive)。

`tool/probe_reader_menu.py` 已在相同真机、合成离线页中复现并验证修复：最终 1.0.1+29 Profile 上执行 4 次菜单切换、每次 10 次采样，窗口保持 2400px、视口保持 914.286dp，图片位移 0px、元素与滚动位置保留。前后记录为 [修复前](reader-menu-1.0.1-before.json) / [修复后](reader-menu-1.0.1-after.json)。最终构建号由修复前 28 递增为 29。

## 本机检查

`verification-1.0.1-before.log` 已复现下载选择按钮点击后消失以及发现页缺少源标题。新增两项回归覆盖真实 DownloadScreen 的选择开关、退出清空、再次进入、封面元素和视口尺寸，以及真实主壳的来源切换与粗体标题。

最终 `flutter analyze --no-pub` 无问题，全量回归 **150 项通过、1 项可选预览跳过**；包含新增的中途阅读/原生系统栏调用回归。新旧专项合计 15 项通过，日志为 `verification-1.0.1-analyze.log`、`verification-1.0.1.log`、`verification-1.0.1-refinement.log`。合成预览和日志在本地保留，不纳入 Git。

## 产物与真机

- Release：21,283,406 字节（20.30 MiB）；Debug：92,650,517 字节（88.36 MiB）。双包均为 1.0.1+29，单 ARM64、minSDK 24、targetSDK 36，包名、标签、调试标志和既有签名核验通过，见 [产物记录](artifacts-1.0.1.json)。Release 比 1.0.0 增加 206,000 字节，约 201 KiB。
- 用户新授权本轮真机性能检查。专用 `tool/profile_scenarios.dart` 只在显式作为构建入口时使用；它加载内存偏好、回环地址提供的合成封面及私有临时目录中的离线页，不读取真实账号或真实离线库，也不进入正式双包的入口。
- Release 与标准 Debug 已同时安装到设备 `22041211AC`、Android 14 / API 34，版本及构建号均为 1.0.1+29。Profile 采样结束后已重新安装标准 Debug，两个产品包均不包含合成 VM 扩展或图标源主图。见 [安装记录](device-install-1.0.1.json)。
- 依赖锁与 1.0.0 一致，见 [依赖记录](dependency-check-1.0.1.json)；本轮未升级或重新下载依赖。源码 ZIP 核对当前实现与图标资源，并排除本机配置、密钥及编译缓存。

## 真机 Profile 帧耗时

设备报告刷新率 120Hz，单阶段帧预算约 8.333ms。发现/书库使用 96 本合成封面，阅读使用 20 张 720×1100 本地图片；滚动先预热再交替滑动 8 次。表中超预算表示 `max(UI 构建耗时, 栅格耗时) > 8.333ms`，不是系统实际丢帧数。

| 场景 | 采样帧数 | UI P95 (ms) | 栅格 P95 (ms) | 超预算帧数 |
| --- | ---: | ---: | ---: | ---: |
| 发现页滚动 | 925 | 2.949 | 3.644 | 0 |
| 离线书库滚动 | 899 | 2.954 | 2.867 | 0 |
| 书库选择开关 12 次 | 598 | 4.419 | 7.186 | 11 |
| 竖向连续阅读滚动 | 857 | 1.078 | 2.294 | 0 |
| 阅读菜单切换 12 次 | 25 | 5.171 | 2.468 | 0 |
| 菜单预热 6 次后再切换 24 次 | 48 | 6.094 | 3.807 | 2 |

选择切换及追加菜单采样仍观察到少量长帧，后者 UI 最大 9.706ms；窗口与图片几何保持稳定。采样末 PSS 为 200,172 KiB，约 195.5 MiB；设备连接 USB 充电，结束时电量 25%、温度 30.2°C、系统热状态 0。当前结果和逐帧数据见 [最终记录](performance-1.0.1-device.json)。修复前 +28 的 [原始记录](performance-1.0.1-device-before.json) 继续保留，当时菜单切换有原生窗口变化；两次帧数会随重绘行为和运行环境变化，不据此给出加速百分比。

本次为单台 Android 真机的合成 Profile 场景，不代表持续显示 FPS、真实上游网络或其他厂商设备表现。本机 1,500 条记录、100 次卡片查询的五次样本中位数为 542µs，单独保存在 `benchmark-1.0.1.log`，不与真机帧耗时混用。

当前 Release / Debug 文件位于 `releases/1.0.1/`，原 1.0.0 及已验收基线继续保留。
