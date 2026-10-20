# kamico 工作交接

更新日期：2026-10-20。工作区 `D:\Projects\JMPicMerge`，客户端在 `Kamico_android/`（原 `jm_mobile/`）。Git 主分支为 `main`，远程为 [hotaruyoi/Kamico](https://github.com/hotaruyoi/Kamico)。本轮 1.0.1+29 已获用户验收，`feature+1.0.0` 合并至 `main`，见 [REPOSITORY.md](REPOSITORY.md)。0.21.0 原交接完整保存在 [history/WORK_HANDOFF_0_21.md](history/WORK_HANDOFF_0_21.md)。

## 当前状态

- 客户端目录已从 `jm_mobile/` 整体迁移为 `Kamico_android/`，现行文档与 Git 忽略路径已更新。源码实现、包名、签名、版本、锁文件、缓存与历史产物保留；新目录静态检查、两项合成回归和 Android 离线配置检查通过，见 [REPOSITORY.md](REPOSITORY.md)。目录迁移及 Git 流程规则随本轮验收合并至 `main`。
- 当前源码为正式版 **1.0.1+29**，按用户反馈补齐下载页选择开关、发现来源粗体标题与新图标，并修复真机阅读菜单切换引起的挖孔窗口变化；双包、真机 Profile 合成采样和安装状态见 [RELEASE_1_0_1.md](RELEASE_1_0_1.md)。静态检查无问题，150 项回归通过、1 项可选预览跳过，新旧专项 15 项通过。用户于 2026-10-20 明确验收，产物源码为 `77afa52`，版本标签为 `v1.0.1`；后续新改动从 `main` 的 1.0.1 新建 `feature+1.0.1`。
- 1.0.0+27 已实现详情排版、书架/历史选择开关与浮动操作条、发现入口拖动排序、阅读菜单覆盖层及关于/许可精简；历史交付记录见 [RELEASE_1_0.md](RELEASE_1_0.md)。当时 ADB 无设备、代理未安装的记录保留为历史事实。Git 的 `v1.0.0` 仍指向原提交。
- **0.23.0 已由用户确认真机验收通过**，作为 Git 初始基线与 `baseline-0.23.0` 标签；原产物与 [UI_0_23.md](UI_0_23.md) 保留。
- **0.22.0+25 已由用户于 2026-10-20 确认真机验收通过**。双源架构和历史验证见 [MULTI_SOURCE_0_22.md](MULTI_SOURCE_0_22.md)，对应快照保留在 `releases/0.22.0/`；当时代理 ADB 无设备及本机探测超时属于历史证据，不再作为该版待办。
- 0.23.0 代理交付时已构建同版本 Release / Debug，包名和既有签名核验通过；静态检查无问题、135 项回归通过、1 项可选预览跳过，另 8 项专项预览通过。当时 ADB 列表为空，代理未安装；后续用户验收确认如上。合成回归不能替代真机上游可用性或真机 FPS 结论。
- 上一版 **0.21.0+24 已由用户验收通过**。该版专项 Profile 对照已取消，不恢复为任务；原 APK、源码、签名和缓存均保留。

## 用户确认的产品规则

1. 在“我的”和发现页标题栏右上角放**圆形图标切源按钮**，背景与底部导航选中底色一致，不显示小字；单击即切换，不使用下拉菜单或确认弹窗，切换后保留当前页面。当前源通过按钮提示/无障碍语义可知。
2. 全局源影响发现、搜索、云端收藏和账号；两个账号保持独立登录，退出/过期只影响对应源。未登录可切入，需要鉴权时再引导登录。
3. 本地历史、收藏和下载共用原入口，**JM / PIC 分区，条目不交错**；各分区保留原排序。本地收藏文件夹共用。
4. 从合并库打开其他来源作品，详情/阅读/评论/收藏绑定作品自己的来源；返回仍保留原全局选择。阅读页“首页”返回当前全局发现页。
5. 切源不暂停原源下载；两源共用队列及并发额度，任务绑定创建时的源。
6. 重启记住当前源，旧安装默认 JM；运行期间发现页及书架分别保留状态，搜索记录/条件/上次查询按源保存。
7. 外观、阅读、预加载、下载设置共用；账号、搜索和连接配置按源隔离。
8. 新 PDF 放 `Downloads/kamico/JM/作品_编号/章节_编号.pdf` / `PIC/`；Debug 根目录 `kamico-debug`。自选目录下也分来源，旧公共文件不搬动。
9. 共用 kamico 已有漫画流程，能力不同的入口按源调整。Pic 没有已确认的云端文件夹、云端历史、JM 周刊/连载、购买及补签入口，不能伪装支持。
10. Pic 聊天、游戏、广场、独立社区、代理网络栈、超分和旧 Qt 数据导入不在本轮范围。
11. 历史页始终显示“本地历史 / 云端历史”，本地复用书架封面卡片及选择栏；JM 云端接口继续保留，Pic 云端页说明未提供接口，可返回本地，不伪造云端记录。
12. 详情封面右侧显示只读点赞图标与粗体数字（JM `likes`、Pic `totalLikes` / `likesCount`），实际 0 与缺失“—”区分；信息块间隔 24dp，Pic 隐藏编号。阅读方向下拉与阅读模式同宽、同默认高度和圆角；大字体允许自适应增高。
13. 书架、本地历史和下载页本地书库的“选择”常驻且保持文案，连续点击开关并在退出时清空勾选。共用操作条浮动在透明外围上，列表按条高保留尾部滚动空间，不因菜单显隐缩小视口。
14. 发现入口顺序由公共外观偏好保存，两源共用；Pic 略过 JM 专属入口。拖动即时保存、可恢复默认，入口 ID 与图标/名称/路由一同排序。
15. 阅读上下控制层不参与漫画尺寸布局；显隐不重建图片元素或控制器，系统栏安全区仅影响覆盖控件。原模式、进度和离线格式继续兼容。
16. 发现页标题为粗体 `Kamico · JM` / `Kamico · Pic`，跟随当前源；新图标使用用户提供的粉色 K 与少女头像，源主图在 `artwork/`，运行包仅包含适配后的平台资源。

## 实现入口与必须保护的行为

- `lib/domain/content_source.dart`：来源；JM 本地键沿用原值，Pic 键为 `pic|remoteId`，上游调用仍用原始 ID。
- `lib/domain/models.dart`：Comic 携带 source / cover；ReaderChapter 携带 source；旧 JSON 缺 source 默认 JM。
- `lib/data/comic_source.dart`：共用漫画流程接口；`jm_client.dart` 为原协议，`pic_client.dart` 为 Pic 签名、普通 JSON、媒体及完整分页。
- `lib/ui/app.dart`：根 AppSession 协调公共资源，`forSource` 返回稳定的来源会话，`active` 供主页面使用。Pic 会话共享本地库、日志、队列及外观通知，持有独立客户端和图片加载器。不可把 active API 捕获进旧路由/任务。
- 根 session 的进度写队列共用；账号凭据各自串行保存。`restore` 先读两源凭据，再恢复队列。
- `lib/data/local_store.dart`：收藏/历史/章节进度带来源键；全局偏好共用，源专属偏好通过 `prefKey` 保存；JM 旧键不改、不迁移文件。
- `lib/data/download_queue.dart`：任务按 comic.key + chapter.id 区分，loadJob 路由至任务来源；原 loadChapter 注入接口保留供既有验证使用。
- `lib/data/image_repository.dart`：Pic 按媒体 URL 获取原始图片，不执行 JM 分片还原、不向媒体主机发送账号 token；JM 原磁盘缓存键保留。
- `lib/ui/reading_navigation.dart`、`discovery.dart`：所有跨源打开先绑定 `forSource(comic.source)`；`comic_browser.dart` 宽屏切书也重新绑定。
- `lib/ui/library_layout.dart`：sourceSections / SourceSection 保证 JM、PIC 连续分区；bookcase / history / downloads 共用。
- `LibrarySelectionLayout` 固定列表尺寸，测量圆角条实际高度作为尾部 inset；`LibrarySelectionToggle` 保留按钮与固定文案。
- `lib/domain/discovery_shortcut.dart` 解析稳定入口标识并兼容异常偏好；`ui/discovery_shortcut_order.dart` 为手柄拖动与串行保存，`discovery.dart` 按标识绑定路由。
- `lib/ui/reader.dart` 的 `_frame` 使用覆盖层，内容层固定全屏；控制层监听存储错误但不影响内容布局。
- `PlatformFiles.readerSystemBars` / Android `MainActivity.kt`：固定挖孔窗口策略，以原生 WindowInsetsController 显隐系统栏。需保护窗口实际尺寸，而非仅保护 Flutter 安全区；真机探针检查页面中途的视口、图片元素与坐标，保留 `tool/profile_scenarios.dart` 的独立合成入口。
- `lib/data/app_licenses.dart` 共用原 LGPL 正文并保留两份来源署名；按依赖闭包去除仅开发使用的包名，`ui/app_licenses.dart` 保留原正文和段落缩进，完整 NOTICES 资产仍在。
- `lib/ui/bookcase.dart`：历史保留本地/云端切换，云端请求按源/账号/连接范围和 generation 校验；删除和撤销按 source key，撤销不覆盖新进度。
- `lib/ui/reader_settings.dart`、`filled_select.dart`：方向控件和模式卡片默认 88dp；模式 ListTile 显式去除主题额外竖向 contentPadding，保持实际高度一致；设置保存逻辑不变。
- `lib/data/platform_files.dart`、Android `PdfDownloads.kt`：通过白名单来源名创建 PDF 子目录，旧文件及旧离线 manifest 继续兼容。
- `test/multi_source_test.dart`：旧数据、同 ID、分页、账号隔离、图片、在途下载、跨源阅读路由及主要 Pic 请求的合成验证。`multi_source_preview_test.dart` 仅在 CAPTURE_UI 时渲染预览。
- `test/ui23_refinement_test.dart`：历史切换/云端分页/迟到结果/按源删除撤销、两源点赞解析与 0/缺失、方向尺寸/持久化/窄屏大字体、标题栏切源位置及颜色；CAPTURE_UI 时生成本版合成预览。

Pic 章节特别注意：参考实现中 ep.order 可能重复，实际读取用升序目录位置；当前章节 ID 同时保存漫画、位置及 ep._id，不能把 ep.order 当唯一标识。目录和图片分页必须取齐，数量不完整要失败，不能发布部分离线章。真实上游行为仍需要连通环境验证。

保留 0.21.0 已验收的填充式 Material 3 组件、阅读三模式及升级兼容、共享封面帧和独立封面池、详情旧内容先显及后台刷新、本地存储快照缓存、进度不重建 MaterialApp、滑杆松手持久化等保护。具体旧行为见归档交接和 README，旧性能待办不复活。

## 操作与交付

遵循根 AGENTS。保留 Qt 两项目、所有编译/依赖缓存及现有历史基线，不执行 clean、升级或依赖重新下载。

- Flutter `D:\Application\Flutter\flutter`，Android SDK `D:\Application\Android-SDK`，JDK `C:\Users\12275\.jdks\temurin-21`。
- 检查：`flutter analyze --no-pub`、`flutter test --no-pub --reporter expanded`。
- 构建：设置既有 ANDROID_HOME / JAVA_HOME / JM_USE_MAVEN_MIRROR，运行 `tool/build_batch.ps1`，下次新版本 build number 大于 29。
- Release 包名 `app.jmpic.jm_mobile`，既有签名；Debug/Profile `.debug` 身份，两者名称、私有数据及默认公共目录继续分开。
- ADB 重新识别设备，不使用历史序列号当在线事实。真机操作优先语义/日志/VM，必要时截图。不得擅自改用户 VPN。
- 本版真实账号写操作由用户发起，自动测试用合成内容。未配置新发行签名、后台下载、更新发布源、桌面发行或 Qt 迁移。
