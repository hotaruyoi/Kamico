# kamico 项目任务交接

更新日期：2026-10-20。工作区：`D:\Projects\JMPicMerge`。本文供新的 Work 对话独立接手；无需读取旧对话。文中客户端相对路径均相对于 `D:\Projects\JMPicMerge\jm_mobile`。

## 1. 接手时的准确状态

- **当前版本：0.21.0+24，用户已确认上一轮真机验收通过。**
- **用户已取消本轮性能验证待办。** 不再等待 ADB，不补做 0.20.2/0.21.0 专项 Profile 对照，不将它恢复为任务或交付阻塞。
- 最新本地检查：`flutter analyze --no-pub` 无问题；完整回归 **113 项通过**。Release、Debug 均已构建、签名及元数据校验，源码已归档。
- 0.21.0 交付时无法连接 ADB，代理未执行安装，也没有采集该版本的真机帧耗时。之后用户亲自报告真机验收通过。验收结论与代理采样记录是两件事，不编造安装记录、设备状态或 FPS。
- 已完成需求全部合入当前版本。**目前没有明确尚未修复的产品 Bug，也没有用户指定的下一轮功能开发任务。** 接手后承接新需求即可；不要继续旧版本文档中的“待验收”。
- 本次交接只更新文档和状态，不改代码、不升级版本、不重新打包、不安装、不清理缓存。`releases/0.21.0/source.zip` 保留原交付快照，其中交付时的“待真机验证”描述属于历史状态；当前状态以本文、`NEXT_ITERATION.md` 和用户最新指令为准。

## 2. 项目目标与范围

将原 JMComic Qt 开源项目的已有 API、图像恢复规则与主要业务能力迁移为 **Flutter 独立客户端**，安卓优先，保留将来支持桌面的能力。客户端直接连接上游 API，无需自建服务端，手机不运行 Python/Qt。

产品名为 **kamico**，图标暂定 **白底、粉色 K**。Release 包名与既有签名保持兼容，改名不改变数据身份。

| 位置 | 用途 |
| --- | --- |
| `D:\Projects\JMPicMerge\jm_mobile` | 当前实际开发、构建与交付的客户端 |
| `D:\Projects\JMPicMerge\JMComic-qt-main` | 原 JMComic Qt 工程，协议、行为、迁移和授权参考 |
| `D:\Projects\JMPicMerge\picacg-qt-main` | 另一份原始参考工程，未参与当前主体迁移，保留 |
| `D:\Projects\JMPicMerge\AGENTS.md` | 工作区长期协作规则，规则后附保留原因 |

工作区根目录当前没有 `.git`，不要假定存在可用的分支或提交记录。历史源码快照在版本交付目录。

## 3. 必须延续的工作约束

1. **保留编译及依赖缓存。** 包括 `build/`、`.dart_tool/`、Gradle/Kotlin、SDK/JDK、Pub 缓存、生成配置、锁文件和本地配置。用户明确要求清理不能导致后续重新下载或重建已有缓存；验证优先使用 `--no-pub`，不要例行 clean、升级依赖或重装环境。
2. **设计遵循 Material Design 3、响应式和现有已验收行为。** 同类按钮、标签、分段选择、筛选器使用无描边纯色填充；轻量工具图标默认透明，保留正常触摸反馈。
3. **交付同版本 Release + Debug。** Release 供用户验收，Debug/Profile 供代理调试，包名和数据隔离。设备可用且任务授权时同时安装，核对版本并冷启动；设备不可用时先完成可执行工作和双包交付，说明实际状态。
4. **真机操作优先 ADB 输入、界面语义、日志、VM 数据。** 仅视觉判断必要时截图，同一状态不重复截图。用户明确要求减少截图消耗。
5. **自动验证使用合成内容和模拟账号。** 真实账号的收藏、评论、签到、购买等写操作由用户发起；不要为了测试写入真实账号。
6. **保留数据升级兼容。** 旧阅读模式设置、旧图片下载、离线库和进度仍需可用，不能把旧字段或格式等同于可删除的废代码。
7. **保留当前交付、最近验收和必要回归基线。** 清理前核对绝对路径、引用和回退用途；不覆盖历史 APK 或源码快照。
8. **验收与测量分开记录。** 本机测试耗时不等于手机 FPS，Debug/不同机型结果不互相替代。0.21.0 的专项性能待办已取消，但未来出现新问题时仍按新问题验证。
9. **计划与实施按用户阶段推进。** 用户要求先讨论时先整理计划；明确开始后完成已授权工作，不为常规可逆操作重复询问确认。设备不可用时继续独立可执行的工作，明确验证边界。

## 4. 最终产品要求与已完成行为

### 4.1 发现、卡片、搜索与筛选

- 首页按上游推荐分组展示，并提供分类、排行榜、最近更新、每周连载、周刊推荐等入口。
- 发现页顶部搜索与快捷入口向下浏览时收起，反向滚动唤出；快捷按钮统一宽度、横向可滑动，超出屏幕的边缘渐隐。
- 卡片提供密度切换，按屏幕和文字缩放响应布局。紧凑模式在常见手机可以显示 4–5 列；这是响应式目标，不是所有屏幕硬编码四列。已有 360dp 四列、390dp 五列测试。
- 搜索支持关键词、类型、排序、年月、分页、历史、编号直达和关联搜索。
- 周刊“档期”和“类型”、连载“星期”和“类型”水平并排，宽度比例 3:2，长文字省略，菜单中展示完整值。
- 共用填充选择器有字段名、当前值、箭头和已选项对勾；圆角 24dp。菜单随按钮定位，空间不足自动适配，长列表内部滚动，高度上限为屏幕 45%。
- 分类和搜索的“筛选和排序”在原按钮下方页面内展开，不再打开大面积底部弹层。草稿与当前结果隔离：**应用才请求，取消不提交，草稿重置仍需应用**。小空间单列，控件区宽度至少 500dp 时两列。
- 展开面板与结果处于同一滚动区域，列表视口尺寸不随展开动画改变。

### 4.2 书架、历史、下载管理

- 保留本地/云端收藏夹管理、查询、排序、批量移动/删除与继续阅读；历史保留每本最近入口及逐章进度。
- 控制区随列表滚动，避免上半部分长期固定挤占内容。
- 多选模式保留左侧封面，复选框放在右侧并使用圆角样式；选择时不重建封面 Element。
- 多选操作栏大圆角 28dp，有两侧、底部间距和悬浮层次，进入/退出有过渡。操作栏预留布局空间，列表末项不被盖住。
- 下载与书架共用条目及操作栏；历史和离线章节的复选框也放到右侧。

### 4.3 作品详情与收藏

- 仅保留“详情”“评论”两个页签，在同页面局部切换，评论按需加载。
- 简介和目录合并在详情中。简介超过四行、标签超过六项时先部分展示；目录默认列表六章、紧凑模式十二章，展开后按需构建，支持收起、排序、搜索和定位最近章节。
- 目录工具栏左侧为章节数量、搜索、正倒序；样式图标在最右侧，默认透明。搜索默认收起，点击向下展开，复用首页 SearchBar 样式；收起会清除查询并关闭键盘，避免隐藏筛选。
- 作品标题在封面上方，清晰封面约占内容宽度 43%、上限 240dp；右侧只显示作者和 JM 号，不重复放总章节数。
- 顶部使用放大的封面背景、高斯模糊和渐变遮罩，平滑过渡到页面背景；背景按页面宽度适配、顶部对齐，sigma 18，不按整页高度裁切或额外过度缩放。返回栏和详情共用背景，避免横向割裂线。
- 清晰封面和模糊背景共用一次请求、一次解码及同一图像帧，并同步显示；失败共用重试。
- 操作栏主阅读按钮约占可用宽度 50%，下载、收藏仅显示图标，各约 15%，触控区至少 48dp；保留边距和剩余空白，不强制铺满。
- 没有历史显示“开始阅读”，有历史显示“继续 第x话”。已删除多余的“从头阅读”界面入口。
- 详情目录条目不显示“未下载”，已下载章节在标题后放带填充底色的圆形对勾；下载统一进入选章面板，不在每章右侧重复放下载按钮。
- 收藏面板可选本地/云端，已登录默认云端，未登录默认本地。仅切换选项不写账号，确认后才加入/取消收藏；云端未登录时引导登录。
- 详情元数据有进程内缓存：鲜活期 5 分钟、最多保留 40 本；到期先显示已有内容再后台刷新，失败仍保留内容并提供重试。账号/连接配置变化及相关写操作触发适当失效，购买前强制复核价格。

### 4.4 阅读

- 仅提供三种模式：**竖向连续滑动（新安装默认）、向右滑动、向左滑动**。旧模式按方向迁移，保持进度兼容。
- 竖向图片无间隙连续衔接，保留缩放、逐章进度、跳页、自动阅读、预加载、离线阅读。
- 阅读页不显示“在线阅读/当前模式”额外提示条；沉浸时无右下角悬浮按钮。点击内容中央占面积 50% 的矩形区域切换菜单，四周点击不唤出，滑动/缩放保持。
- 顶部为返回、房子图标返回首页、较小标题、章节目录、最右侧设置；已移除原三点菜单及其图片导出入口。
- 从“继续阅读”进入，返回箭头和系统返回均到该作品详情，换章后保持此路径。房子按钮清理阅读导航栈并选择发现页。
- 阅读设置有固定标题/关闭按钮，内部内容滚动；按常亮/方向、三种模式、自动阅读/预加载分组。最大宽度 640dp、高度 88% 屏幕，统一填充圆角控件。
- 设置开关保留页码；重复选择当前模式不重建翻页控制器。滑杆拖动只更新面板预览，松手后持久化，避免连续写入及重建阅读页。

### 4.5 下载、PDF 与设备文件

- 下载默认每章生成一个 PDF，图片按阅读顺序、原比例、等宽无边距排列，PDF 建议连续竖向布局；外部阅读器可覆盖其显示方式。
- 不再提供 PNG 下载格式选项。旧图片下载仍可离线读或另存 PDF，不在升级时批量强制转换。
- Release 默认公共路径：`Downloads/kamico/作品名称_编号/章节名称_编号.pdf`；Debug/Profile 使用 `Downloads/kamico-debug/`。系统可能将 Downloads 显示成 Download 或“下载”。
- Android 10+ 使用 MediaStore.Downloads 发布，Android 7–9 需要时申请公共存储权限。用户选过导出目录时遵循其选择。
- 内部离线缓存、下载断点与公共 PDF 独立。删除缓存或卸载不删除公共 PDF；导入仅读取用户选择目录，不移动/删除源文件。
- 队列支持选章/批量编号、并发限制、暂停/继续/取消/重试和重启恢复。**目前需要应用保持前台，没有后台下载服务、通知或自动唤醒。**

### 4.6 账号、外观、评论与动效

- 登录界面保留登录和系统浏览器打开原站注册入口；应用内注册、找回密码、邮箱验证已移除。密码不落盘，令牌安全存储。
- “我的”头像居左，账号标识大字显示（优先用户名、缺失时 UID），长内容自适应缩小，不额外写“已登录”；四个入口统一图标文字样式。
- 保留资料、签到、评论/回复/草稿与购买金额确认；真实写操作由用户发起。
- 评论时间在卡片右上角，以浅灰小字区分；正文 17sp、约 1.55 行高，跟随字号缩放。
- 外观支持系统/浅/深、主题色、简中/繁中/英文、字体缩放/粗体/斜体。字体默认系统，从系统开放的设备字体列表选择，按选择加载，不可用时回退；不能读取其他应用私有字体，部分厂商字体可能不可见。
- 全应用统一 Material 原生按压/选择反馈、菜单动画、面板和对话框过渡。公共按钮状态 160ms；局部展开 240ms；弹层进入 240ms/退出 200ms；自定义动画尊重系统减少动画设置。
- 不为滚动卡片额外添加入场动画、常驻循环动画或动态模糊，防止无谓绘制开销。

## 5. 架构与已经解决的性能问题

主业务和界面为 Dart/Flutter，使用 ChangeNotifier 与显式依赖注入。`AppSession` 集中协调 API、LocalStore、图像、下载队列等。Kotlin 文件是 Android 原生能力桥接（PDF 公共目录、系统字体、文档选择、常亮/隐私等），不是改成 Kotlin 编写主体 UI。

应继续保护的修复：

| 问题（已关闭） | 当前实现及注意点 |
| --- | --- |
| 卡片滚动重复解析整份历史、收藏、章节进度 | LocalStore 按偏好数据版本缓存只读快照，提供索引查询；避免每张卡片重新解析 JSON |
| 保存阅读进度重建 MaterialApp 与主题 | 外观通知与普通会话通知分离；进度通知复用应用/导航子树 |
| 小封面统一 400px 解码 | 按显示物理宽度选取 64px 档位，范围 64–400px |
| 发现页滑动速率跳变 | 使用同一个 CustomScrollView 和 SliverFloatingHeader 的 overlay snap；避免在视口外用 AnimatedSize 改变其高度 |
| 滚动期间卡片重复构造 | 布局宽度在外层计算，不随 sliver 滚动反复生成现有卡片；宽度改变仍响应式更新 |
| 清晰封面与模糊背景分次出现 | DetailArtwork 持有一条 ImageStream，两处 RawImage 共用 ImageInfo/ui.Image；离开时解除监听并释放帧句柄 |
| 阅读大图挤出首页、详情封面 | 从原 100 MiB 解码 LRU 预算拆分：普通/阅读 84 MiB，封面 16 MiB、最多 96 项；CoverImageProvider 统一访问独立封面池 |
| 详情到期后等待接口，像重新加载封面 | 最多 40 本的进程内旧详情先显示、后台刷新，账号隔离及购买复核保留 |
| 设置滑杆每次拖动写偏好/重建阅读页 | 局部预览，onChangeEnd 保存；保持当前模式时复用阅读控制器 |

封面 LRU 限额不代表应用总内存上限，活动图片、编码字节和 GPU 另有生命周期。系统内存压力、容量淘汰或进程重启后仍可重新加载；**没有新增永久封面磁盘缓存**。阅读页另有磁盘缓存，二者不是同一机制。

现有网络容错仅在 GET 连接异常、超时或 5xx 时换线，POST 不自动重放；配置的 API 域名视为可信，GET 换线可能携带令牌。修改连接配置会退出账号。接口、登录和日志变更需保持这些语义，记录证据时脱敏凭据。

0.17.0 Release 原掉帧已获用户确认解决；0.21.0 真机验收也已通过。专项 Profile 采样已取消，保留现有回归保护即可，未来有新问题再诊断。

## 6. 代码与资料定位

以下均在 `D:\Projects\JMPicMerge\jm_mobile` 下：

| 路径 | 修改/排查用途 |
| --- | --- |
| `lib/main.dart`、`lib/ui/app.dart` | 启动、缓存配置、AppSession、主题、主导航 |
| `lib/domain/models.dart`、`card_layout.dart`、`reader_options.dart` | 业务模型、响应式密度、三模式与旧值迁移 |
| `lib/data/jm_protocol.dart`、`jm_client.dart`、`api_config.dart` | 上游协议/图像恢复、API/缓存/账号、连接配置 |
| `lib/data/local_store.dart` | 偏好、本地收藏、历史及逐章进度的快照缓存 |
| `lib/data/image_repository.dart` | 阅读图片请求合并、预加载与磁盘缓存 |
| `lib/data/download_queue.dart`、`download_repository.dart`、`chapter_pdf.dart` | 队列、离线落盘与 PDF |
| `lib/ui/design_system.dart`、`motion.dart`、`filled_select.dart` | 公共 Material 主题、动效、FilledSelect/OptionGrid |
| `lib/ui/discovery.dart`、`search_filters.dart` | 发现/分页/分类/周刊/搜索与筛选草稿 |
| `lib/ui/library_layout.dart`、`bookcase.dart`、`downloads.dart` | 通用书架条目/选择栏、书架/历史、下载页 |
| `lib/ui/detail_reader.dart`、`detail_artwork.dart` | 详情布局/目录/收藏及共享封面图像 |
| `lib/ui/cover_image.dart`、`cover_image_provider.dart` | 封面显示、按宽解码及独立缓存池 |
| `lib/ui/reader.dart`、`reader_settings.dart`、`reading_navigation.dart` | 阅读页、设置局部状态、统一进入/返回路径 |
| `lib/ui/chapter_download_sheet.dart` | 统一选章下载面板 |
| `lib/ui/comments_body.dart`、`comment_editor.dart`、`account*.dart` | 懒评论、草稿、登录/资料/签到 |
| `lib/ui/preferences.dart`、`font_picker.dart`、`lib/data/system_fonts.dart` | 外观与设备字体 |
| `lib/data/platform_files.dart` | Dart 侧 Android MethodChannel 桥接 |
| `android/app/src/main/kotlin/app/jmpic/jm_mobile/` | MainActivity、PdfDownloads、SystemFontBridge、DocumentBridge |
| `android/app/build.gradle.kts`、`lib/app_identity.dart` | 包名、签名、Debug/Profile 身份与下载目录 |
| `android/app/src/main/res/`、`tool/generate_brand_icon.dart` | 图标/启动资源与图标生成工具 |
| `assets/i18n/en.json`、`zh_TW.json`、`lib/ui/translations.dart` | 语言词典与运行时模板翻译 |
| `test/ui21_interaction_test.dart`、`reader_modes_test.dart` | 本轮交互、阅读设置/控制器与三模式真实手势 |
| `test/performance_regression_test.dart`、`detail_artwork_test.dart`、`detail_cache_test.dart` | 已修复性能和缓存的回归保护 |
| `test/perf/local_store_benchmark.dart` | 本机查询基准，不是 FPS 测试 |
| `tool/build_batch.ps1` | 版本同步、ARM64 双包构建、符号分离和源码归档 |
| `pubspec.yaml`、`lib/app_version.dart` | 当前版本号；交付脚本同时更新 android/local.properties |
| `LICENSE`、`THIRD_PARTY_NOTICES.md`、`third_party/` | 授权与来源，迁移时保留 |

按需读取：`docs/UI_0_21.md`（最新改动/证据）、`COVER_CACHE_0_20_2.md`（图片池与详情刷新）、`ARTWORK_SYNC_0_20_1.md`（同步图像）、`DISCOVERY_SCROLL_FIX.md`（滚动速率原因）、`DETAIL_TOOLBAR.md`（目录搜索）、`PERFORMANCE_0_17.md`（性能/体积基线）、`DEBUGGING.md`（双版本调试）、`CLEANUP_REPORT.md`（缓存保护与清理）。这些文件位于同一 `docs/` 目录。

历史记录可能包含当时未验收、旧布局或旧模式描述；只有追溯原因时读取，不从中重新生成任务。当前规范以本文和现有实现为准。

## 7. 本机构建、检查与调试

### 7.1 已有环境

- Windows / PowerShell；项目目录 `D:\Projects\JMPicMerge\jm_mobile`。
- Flutter **3.44.8**、Dart **3.12.2**：`D:\Application\Flutter\flutter`。
- Android SDK：`D:\Application\Android-SDK`，当前 compile/target SDK 36；现有 build-tools 包含 35.0.0，可用 aapt2/apksigner。
- JDK 21：`C:\Users\12275\.jdks\temurin-21`。Gradle/Kotlin、Pub 依赖已缓存。
- 当前安卓产物最低 API 24（Android 7.0），仅 `arm64-v8a`。保留 Windows runner，但桌面发行不是已完成承诺。

### 7.2 日常检查

```powershell
Set-Location -LiteralPath 'D:\Projects\JMPicMerge\jm_mobile'
& 'D:\Application\Flutter\flutter\bin\flutter.bat' analyze --no-pub
& 'D:\Application\Flutter\flutter\bin\flutter.bat' test --no-pub --reporter expanded
```

测试按变更选用有效回归，避免镜像实现的无意义测试。无需因为接手或只修改文档而重新运行编译。Flutter 启动、Dart format 和构建可能需写工作区外已有 SDK/遥测缓存；在权限限制下使用正规执行审批，不以清缓存或重新下载解决。PowerShell 使用任务变量，避免覆盖 `$HOME` 等系统变量。

### 7.3 新版本交付（仅收到新开发任务时执行）

```powershell
$env:ANDROID_HOME = 'D:\Application\Android-SDK'
$env:JAVA_HOME = 'C:\Users\12275\.jdks\temurin-21'
$env:JM_USE_MAVEN_MIRROR = 'true'
# $nextVersion 按下一轮需求确定；$nextBuildNumber 必须大于当前 24。
.\tool\build_batch.ps1 -Version $nextVersion -BuildNumber $nextBuildNumber
```

脚本默认同时构建 Release/Debug，使用 `--no-pub`、单 ARM64；Release 分离调试符号。输出在 `releases/<版本>/`，标准构建输出另在 `build/app/outputs/flutter-apk/`。`-Mode debug` 可单独构建调试包，`-Mode release -AnalyzeSize` 用于专门体积分析，不与符号分离放在同一次构建。

沿用既有 Maven 镜像开关和 Kotlin 增量编译关闭设置，避免 Windows 跨盘缓存问题。交付时核对包名、版本、签名、调试标记及源码快照一致性。不要覆盖 0.21.0 或旧基线来伪装新交付。

### 7.4 双版本身份与设备操作

| 用途 | 名称 | 包名 | Activity |
| --- | --- | --- | --- |
| 用户验收 | kamico | app.jmpic.jm_mobile | app.jmpic.jm_mobile.MainActivity |
| 代理调试（Debug/Profile） | kamico Debug | app.jmpic.jm_mobile.debug | app.jmpic.jm_mobile.MainActivity |

两者账号、私有数据、偏好和下载目录隔离。**当前 Release 仍使用既有开发签名**，尚未配置正式发行密钥；改变包名或签名会影响覆盖升级。

最后已知调试机为小米 22041211AC / Android 14（曾用序列号 `NJ4X4DHIUWPFLNZD`），较早掉帧反馈的 vivo X300 Pro 是另一台。连接后重新识别设备，不将旧序列号当成当前在线事实。手机网络全程使用用户 VPN 代理，避免擅自改网络环境。

以下仅供未来获授权且设备已连接时使用，本次交接不执行：

```powershell
$adb = 'D:\Application\Android-SDK\platform-tools\adb.exe'
& $adb devices -l
# 将 $serial 设置为当前实际设备；切勿误装到别的设备。
& $adb -s $serial install -r 'releases/<版本>/app-arm64-release.apk'
& $adb -s $serial install -r 'releases/<版本>/app-arm64-debug.apk'
& $adb -s $serial shell am start -n 'app.jmpic.jm_mobile.debug/app.jmpic.jm_mobile.MainActivity'
& 'D:\Application\Flutter\flutter\bin\flutter.bat' run --debug --no-pub -d $serial
```

已有 flutter run 会话中输入 `r` 热重载。Profile 使用 `.debug` 身份，会替换 Debug，因此需要时调试后恢复 Debug，Release 始终用于用户验收。不要把仅热重载的结果当成已安装新版，交付应重新构建并核对实际版本。

## 8. 当前交付与证据

完整路径前缀：`D:\Projects\JMPicMerge\jm_mobile\`。

| 文件/目录 | 内容 |
| --- | --- |
| `releases/0.21.0/app-arm64-release.apk` | 0.21.0+24，21,010,318 bytes，20.04 MiB，非 debuggable |
| `releases/0.21.0/app-arm64-debug.apk` | 同版本，92,352,735 bytes，88.07 MiB，独立调试身份 |
| `releases/0.21.0/source.zip`、`symbols/`、`build-*.log` | 原交付源码、Release 包外符号和双构建日志；本次文档接手不重写快照 |
| `docs/artifacts-0.21.0.json` | aapt2 元数据、SHA-256、调试标记和签名记录，Release 证书与 0.20.2 一致 |
| `docs/verification-0.21.0.log`、`verification-0.21.0-analyze.log` | 113 项回归和静态检查通过 |
| `docs/verification-0.21.0-interactions.log` | 新增交互及实际阅读设置回归 |
| `docs/baseline-source-check-0.21.0.json` | 与 0.20.2 的关键缓存/存储/API 源码一致性 |
| `docs/baseline-comparison-0.21.0.log`、`benchmark-0.21.0.log` | 本地查询配对基准与已有基准，不作为手机性能结论 |
| `docs/previews/0.21.0/` | 合成 UI 预览，封面是测试占位，不是真实账号/内容 |
| `releases/0.20.2/` | 本轮直接对照基线，保留；其他已保留版本按 README 的策略维护 |

Release SHA-256：`2F325640C5413D811DB0D353986212815FED35C5E14DB8F8D32744353F2BA861`。

Debug SHA-256：`3182B075529B90594B0CD98A4AB64BB0D78EDDC2B731BF42A2CE73FFB5873094`。

Debug 较大包含调试运行能力，当前 Release 约 20 MiB，与上版基本相同；不存在把 Debug 体积当作正式版体积的新待办。

## 9. 尚未解决、延期与排除项

**当前没有已知、明确待修复的产品缺陷；下一轮功能需求尚未提出。** 下表是已知能力边界或延期条件，不能当成本次授权的实施清单。

| 项目 | 状态与后续触发条件 |
| --- | --- |
| 0.21.0 专项性能验证 | **已由用户取消；不是待办。** 真机体验验收通过，不再等待 ADB 补采样 |
| 自动检查更新 | 尚无 Flutter 版 APK 发布仓库/更新清单，用户选择先做版本信息和日志；发布地址确定后再接入 |
| 正式签名与分发 | 未配置正式发行密钥/渠道；当前开发签名保持既有覆盖升级兼容 |
| 后台下载服务 | 尚无，当前要求前台；若用户明确提出再设计服务/通知/恢复策略 |
| 桌面发行 | 后续目标，runner 保留，未承诺发行级支持 |
| 旧 Qt 用户数据迁移 | 后续平台工作，未开始，需用户明确需求 |
| 超分、NAS、网络增强 | 用户明确排除，未经新指令不实现 |
| 厂商/旧系统兼容 | 已知设备字体可见性、外部 PDF 显示偏好和旧安卓权限差异属于平台边界；有具体新报告再验证，不维护无限待测清单 |

## 10. 新 Work 的继续方式

1. 以 **0.21.0+24 已验收**为出发点，遵循工作区 AGENTS，检查当前源码版本是否仍匹配本文。
2. 如用户尚未提出新任务，保持当前完成状态；不要自动恢复旧版待办、专项性能测试或安装任务。
3. 收到新功能/缺陷后，按第 6 节定位组件，使用现有依赖实现并保护第 4–5 节已验收行为；需要历史原因再读取对应记录。
4. 完成适当回归，更新 README、NEXT_ITERATION 和验证记录；有代码交付时生成同版本双包。设备不可用时明确实际验证范围，继续完成独立可执行部分。
5. 遇到与本文不同的新用户决定，以新指令为准并更新状态入口。不要把新的测试发现、平台限制或用户验收推断成不存在的量化测量结果。
