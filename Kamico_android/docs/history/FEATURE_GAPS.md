> 历史归档：描述对应版本当时的状态，不作为当前待办或长期规则。当前行为见 [客户端说明](../../README.md)，未完成事项见 [下一版待办](../NEXT_ITERATION.md)。早于 0.15 的交付副本和截图已按清理策略移除，旧路径仅供历史追溯。

# 原版功能对照与实施状态

更新日期：2026-10-18。第一版 0.1.0 已验收；后续按照用户授权分为 6 批实施，0.7.0 已验收，当前 0.8.0 进行 Material 3 界面改进。

0.7.0 补齐时的原清单 40 组功能：**32 组已实现代码和自动化验证，1 组部分完成（40：版本与日志已完成，更新检查按用户要求延期），7 组本轮排除（31–37）**。实现状态不等于真机或真实账号已验收。各批安装包、检查证据与限制见 [BATCHES.md](BATCHES.md)。

## 统计口径

- 每项是可以排期并验收的功能或功能组，不是接口、文件或按钮数量，也不代表等量工作量。
- “待补齐”表示第一版已有基础能力，并非完全缺失。
- 原版有请求类但没有发现界面调用的能力（例如部分博客、随机推荐接口），不直接算作已完成的原版用户功能。
- 这是当前对照范围下的排期清单，不声称穷尽每个桌面快捷键和细小设置；后续新增条目应保留编号。
- 原版源码存在该能力，不代表上游接口目前仍能成功调用；开发时按功能验证。
- 热搜独立接口尚未确认，不计入 40 项。搜索历史与提示不应冒充全站热搜。
- 安卓后台服务、下载通知、相册/文件授权适配、正式签名与分发，以及旧数据导入迁移，属于平台或迁移工作，不加入这 40 项原版功能差距。它们可能是对应功能交付时的必要子任务。
- Windows/Linux/macOS 打包、托盘、多窗口和桌面快捷键按“后续桌面阶段”处理，不纳入安卓优先的本次数量。

## 第一版盘点基线汇总

| 分类 | 合计 | 未实现 | 待补齐 |
|---|---:|---:|---:|
| 发现与检索 | 11 | 8 | 3 |
| 账号、书架与互动 | 9 | 7 | 2 |
| 阅读体验 | 5 | 4 | 1 |
| 下载与本地书库 | 5 | 1 | 4 |
| 超分与 NAS | 3 | 3 | 0 |
| 网络与通用设置 | 7 | 5 | 2 |
| 总计 | 40 | 28 | 12 |

## 当前逐项状态

| 编号 | 分类 | 功能 | 状态 | 实现与限制 | 原版依据 |
|---|---|---|---|---|---|
| 01 | 发现与检索 | 首页推荐分组 | 已实现 | 保留推荐分组的标题、类型与独立完整列表入口。 | [源码](../../../JMComic-qt-main/src/view/index/index_view.py) |
| 02 | 发现与检索 | 最近更新列表 | 已实现 | 最近更新独立列表、分页与跳页。 | [源码](../../../JMComic-qt-main/src/view/index/index_view.py) |
| 03 | 发现与检索 | 按星期查看连载 | 已实现 | 按星期与漫画类型筛选连载。 | [源码](../../../JMComic-qt-main/src/view/index/index_view.py) |
| 04 | 发现与检索 | 周刊与档期筛选 | 已实现 | 周刊档期与类型筛选、分页。 | [源码](../../../JMComic-qt-main/src/view/index/week_view.py) |
| 05 | 发现与检索 | 分类和子分类 | 已实现 | 分类、子分类、关键词与排序。 | [源码](../../../JMComic-qt-main/src/view/category/category_view.py) |
| 06 | 发现与检索 | 排行榜 | 已实现 | 分类排序对应总/月/周/日榜。 | [源码](../../../JMComic-qt-main/src/view/category/category_view.py) |
| 07 | 发现与检索 | 高级搜索 | 已实现 | 搜索范围、排序、年月筛选与分页。 | [源码](../../../JMComic-qt-main/src/view/search/search_view.py) |
| 08 | 发现与检索 | JM 编号直达 | 已实现 | 识别 JM 编号并打开详情。 | [源码](../../../JMComic-qt-main/src/view/search/search_view.py) |
| 09 | 发现与检索 | 搜索历史与本地输入提示 | 已实现 | 保留最近搜索词，支持筛选、复用与清空。 | [源码](../../../JMComic-qt-main/src/component/line_edit/search_line_edit.py) |
| 10 | 发现与检索 | 详情信息与关联搜索 | 已实现 | 作者、标签、作品与角色关联搜索。 | [源码](../../../JMComic-qt-main/src/view/info/book_info_view.py) |
| 11 | 发现与检索 | 付费漫画价格与购买 | 已实现 | 显示价格与购买状态，提交前确认金额并复核价格。 | [源码](../../../JMComic-qt-main/src/view/info/book_info_view.py) |
| 12 | 账号、书架与互动 | 账号注册 | 已实现 | 0.8.0 按用户要求改为系统浏览器打开原网站注册，不再提供应用内注册表单。 | [源码](../../../JMComic-qt-main/src/view/user/register_new_widget.py) |
| 13 | 账号、书架与互动 | 邮箱验证与找回密码 | 按用户移除 | 0.8.0 按用户要求移除登录页的邮箱验证、重发邮件与找回密码入口。 | [源码](../../../JMComic-qt-main/src/view/user/user_manager_new_widget.py) |
| 14 | 账号、书架与互动 | 用户资料展示 | 已实现 | 头像、账号、等级、经验、金币和收藏额度；资料来自最近登录。 | [源码](../../../JMComic-qt-main/src/component/widget/navigation_widget.py) |
| 15 | 账号、书架与互动 | 签到与补签 | 已实现 | 日历、今日签到、补签及可选启动自动签到。 | [源码](../../../JMComic-qt-main/src/component/widget/navigation_widget.py) |
| 16 | 账号、书架与互动 | 云端收藏夹管理 | 已实现 | 云端收藏夹浏览、排序、新建、删除、移动与批量管理。 | [源码](../../../JMComic-qt-main/src/view/user/favorite_view.py) |
| 17 | 账号、书架与互动 | 本地收藏与分组 | 已实现 | 本地收藏分组、移动和删除分组时保留漫画。 | [源码](../../../JMComic-qt-main/src/view/user/local_favorite_view.py) |
| 18 | 账号、书架与互动 | 云端观看历史 | 已实现 | 云端观看历史分页。 | [源码](../../../JMComic-qt-main/src/view/history/remote_history_view.py) |
| 19 | 账号、书架与互动 | 评论与回复 | 已实现 | 漫画评论、回复和我的评论；网页内容按纯文本展示。 | [源码](../../../JMComic-qt-main/src/view/comment/comment_view.py) |
| 20 | 账号、书架与互动 | 本地历史管理 | 已实现 | 本地历史检索、分页、选择和批量删除。 | [源码](../../../JMComic-qt-main/src/view/history/history_view.py) |
| 21 | 阅读体验 | 更多阅读模式 | 已实现 | 8 种单页、双页、反向及连续阅读模式。 | [源码](../../../JMComic-qt-main/src/view/read/read_enum.py) |
| 22 | 阅读体验 | 自动翻页与滚动 | 已实现 | 定时翻页/滚动及间隔控制，后台停止。 | [源码](../../../JMComic-qt-main/src/view/read/read_tool.py) |
| 23 | 阅读体验 | 阅读器内切换章节 | 已实现 | 阅读器章节列表、上一章/下一章与离线章节导航。 | [源码](../../../JMComic-qt-main/src/view/read/read_tool.py) |
| 24 | 阅读体验 | 单张图片保存与复制 | 已实现 | 安卓文件选择器保存、内容 URI 复制与分享。 | [源码](../../../JMComic-qt-main/src/view/read/read_view.py) |
| 25 | 阅读体验 | 阅读预加载与缓存策略 | 已实现 | 前后 0–3 页预加载、请求去重、获取并发限制和磁盘缓存。 | [源码](../../../JMComic-qt-main/src/view/read/read_pool.py) |
| 26 | 下载与本地书库 | 整本、选章和批量下载 | 已实现 | 整本、选章、多漫画编号下载。 | [源码](../../../JMComic-qt-main/src/view/download/download_some_view.py) |
| 27 | 下载与本地书库 | 持久化下载任务管理 | 已实现 | 持久化队列、并发限制、暂停/继续、取消、重试与重启恢复；当前前台运行。 | [源码](../../../JMComic-qt-main/src/view/download/download_view.py) |
| 28 | 下载与本地书库 | 下载列表与文件管理 | 已实现 | 任务筛选，本地章节搜索排序、批量导出、删除记录或文件。 | [源码](../../../JMComic-qt-main/src/view/download/download_view.py) |
| 29 | 下载与本地书库 | 下载目录、命名与格式选项 | 已实现 | 应用内部可靠离线索引，SAF 选择外部导出目录、命名方式及新任务 PNG 转换。 | [源码](../../../JMComic-qt-main/src/view/setting/setting_view.py) |
| 30 | 下载与本地书库 | 导入与管理本地漫画 | 已实现 | 导入选定目录及子目录图片，生成离线章节并加入本地分组。 | [源码](../../../JMComic-qt-main/src/view/tool/local_read_view.py) |
| 31 | 超分与 NAS | 阅读及封面超分 | 本轮排除 | 阅读/封面图像增强、模型和倍率选择，以及下载自动超分。 | [源码](../../../JMComic-qt-main/src/view/tool/waifu2x_tool_view.py) |
| 32 | 超分与 NAS | 本地图像批量超分 | 本轮排除 | 批处理任务、输入输出目录、格式和模型选择。 | [源码](../../../JMComic-qt-main/src/view/tool/batch_sr_tool_view.py) |
| 33 | 超分与 NAS | NAS 连接与传输 | 本轮排除 | WebDAV、SMB/SMB3 配置及漫画上传任务。 | [源码](../../../JMComic-qt-main/src/view/nas/nas_view.py) |
| 34 | 网络与通用设置 | 代理设置 | 本轮排除 | HTTP、SOCKS5、系统代理及登录相关代理配置。 | [源码](../../../JMComic-qt-main/src/view/user/login_proxy_new_widget.py) |
| 35 | 网络与通用设置 | 线路测速与 CDN 分流 | 本轮排除 | 已有手动域名配置和 GET 换线；缺测速、优选 IP、CDN 分流及动态配置更新等。 | [源码](../../../JMComic-qt-main/src/view/user/login_proxy_new_widget.py) |
| 36 | 网络与通用设置 | 自定义 DNS 与 DoH | 本轮排除 | DNS 查询、DoH 地址和解析配置。 | [源码](../../../JMComic-qt-main/src/view/tool/doh_dns_view.py) |
| 37 | 网络与通用设置 | HTTP/3 与 ECH | 本轮排除 | 原版 curl_cffi 提供的可选网络能力；安卓需重新评估实现方式。 | [源码](../../../JMComic-qt-main/src/server/req.py) |
| 38 | 网络与通用设置 | 标题和标签屏蔽 | 已实现 | 屏蔽词维护，标题与标签独立开关；标签仅对接口实际提供的数据生效。 | [源码](../../../JMComic-qt-main/src/view/tool/forbid_words_view.py) |
| 39 | 网络与通用设置 | 外观与语言设置 | 已实现 | 系统/浅/深主题、主题色、简中/繁中/英文界面、字体与缩放、封面大小和标题行数。 | [源码](../../../JMComic-qt-main/src/view/setting/setting_view.py) |
| 40 | 网络与通用设置 | 更新检查与日志界面 | 部分完成 | 版本与许可信息；300 条本地运行日志，搜索/分类/复制/清空；更新检查等待发布源。 | [源码](../../../JMComic-qt-main/src/view/help/help_view.py) |

## 后续验收

0.7.0 已验收；0.8.0 按用户新要求调整账号入口，详见 [界面改进](UI_0_8.md)。真实账号操作、网站表单、安卓系统目录/分享及生命周期需人工验收；后台下载服务、正式签名分发、旧数据库迁移和桌面打包仍属于后续平台工作。


