> 历史归档：描述对应版本当时的状态，不作为当前待办或长期规则。当前行为见 [客户端说明](../../README.md)，未完成事项见 [下一版待办](../NEXT_ITERATION.md)。早于 0.15 的交付副本和截图已按清理策略移除，旧路径仅供历史追溯。

# 源码分析与重构方案

## 判断依据

原项目 README 将其描述为 Windows/Linux/macOS 的 Qt 客户端，核心功能为看图与下载。`src/requirements.txt` 使用 Python、PySide6、curl_cffi、Pillow、jmcomic==2.6.20 及桌面超分/NAS 依赖。

`src/server/` 是客户端请求调度层，不是可以直接部署的 HTTP 服务。它依赖 QtOwner、全局 Setting、TaskBase 和信号回调；直接引入安卓会连带桌面事件循环和依赖。重构复用协议行为，不在手机运行 Python/Qt。

选择 Flutter：用户已选择安卓优先、后续支持桌面的独立客户端方向。Flutter 官方支持多平台应用；平台能力可通过插件/原生扩展接入：[架构概览](https://docs.flutter.dev/resources/architectural-overview)、[支持平台](https://docs.flutter.dev/reference/supported-platforms)。

## 协议来源与迁移状态

| 能力 | 原项目依据 | 接口或算法 | 新版状态 |
|---|---|---|---|
| 首页 | `src/server/req.py::GetIndexInfoReq2` | GET `/promote` | 已接入 |
| 最近更新 | `GetLatestInfoReq2` | GET `/latest` | 最近更新入口、分页和跳页已接入 |
| 搜索 | `GetSearchReq2` | GET `/search`，search_query/page/o/lang | 范围/排序/年月筛选、编号直达与历史已接入 |
| 分类/排行 | `GetCategoryReq2` / `GetSearchCategoryReq2` | `/categories` / `/categories/filter` | 已接入，真实账号操作待人工验收 |
| 详情 | `GetBookInfoReq2` | GET `/album`，id/lang/comicName | 已接入 |
| 阅读 | `ReadBookInfoReq2` / `tools/tool.py::ParseReadBook2` | GET `/comic_read`，id/lang | 已接入 |
| 旧章节 | `GetBookEpsInfoReq2` 的 handler | `/chapter` 的旧解析已注释并标记淘汰 | 不作为当前阅读来源 |
| 图片分块参数后备 | `GetBookEpsScrambleReq2` | `/chapter_view_template`，另用签名参数 | 尚未接入；缺失 scramble_id 时明确报错 |
| 登录 | `LoginReq2` / `ParseLogin2` | POST `/login`，username/password，jwttoken | 已接入 |
| 收藏列表/切换 | `GetFavoritesReq2` / `AddAndDelFavoritesReq2` | GET/POST `/favorite` | 收藏夹分页/排序/新建/删除/移动与切换已接入 |
| 收藏夹管理 | `*FavoritesFoldReq2` | POST `/favorite_folder`，add/del/move | 已接入，真实账号操作待人工验收 |
| 评论/历史/签到/活动 | `src/server/req.py` | 相应请求类 | 云端历史、评论与签到已接入；本地历史支持管理 |
| 注册/找回密码 | RegisterReq / ResetPasswordReq | 网页 form + cookie/验证码 | 网页会话、表单及浏览器入口已接入，当前环境 TLS 握手失败，待人工验收 |
| 图像恢复 | `tools/tool.py::GetSegmentationNum/SegmentationPicture` | MD5 确定条带数量，反转条带，保留余数行 | 已移植到 Dart isolate |
| 下载 | `src/task/task_download.py` | 客户端任务调度/持久化 | 持久化队列、并发/暂停/继续/取消/重试、批量下载与离线索引；当前要求前台运行 |
| 超分/NAS | task / view/tool / view/nas | Vulkan / SMB / WebDAV 等 | 本轮排除 |

以上“已接入”指已实现客户端代码和离线测试，不能代替真实上游验收。

## 协议兼容细节

- 默认请求 token 为 MD5(timestamp + `18comicAPP`)，tokenparam 为 timestamp 与 HeaderVer（本地为 2.1.11）。依据本地 `req.py::GetHeader`。
- 原项目响应解密委托给 `jmcomic==2.6.20`。已检查该 PyPI wheel 的 `jm_config.py` 和 `jm_toolkit.py`：数据参数为 `185Hcomic3PAPP7R`，密钥为 MD5(timestamp + 参数) 的 32 字节十六进制文本，AES-256-ECB，末尾去 PKCS7 padding。
- 固定版本 wheel SHA256：`5319686bd7790f769294d0f4ad5cc17081a97e6e892c8a6ad333a20cf2ab085e`。[PyPI 2.6.20](https://pypi.org/project/jmcomic/2.6.20/)
- 上游 master 已有签名参数变动，不能拿 master 的值直接覆盖本地协议。设置提供高级参数，以便针对明确验证过的上游版本调整。
- 图片分割数按本地 Qt 的 `chapterId > 421926` 分支移植；上游库 master 的相邻边界写法不同。测试固定覆盖 421926/421927，避免无意改变兼容行为。
- GET 仅在连接异常、超时或服务器 5xx 时换线路。POST 不自动重放，避免收藏切换等操作因超时被执行两次。
- 所有配置域名必须为 HTTPS origin；不关闭证书验证。API bearer 不发送给图片域名。
- 本版没有重现 curl_cffi 的 TLS 指纹、HTTP/3、ECH、自定义 DNS/CDN 分流与代理支持；特定网络环境下原版可连接并不代表新版一定可连接。

## 架构

UI / 应用状态 → JmClient / 下载模块 → HTTP + 协议模块 / 本地存储。

`JmClient` 向页面提供 home/search/detail/chapter/login/favorites 等语义操作，将签名、解密、错误和返回值解析封装在内部。下载模块隐藏页文件、部分下载恢复、完成索引的发布规则；页面只提交章节并观察进度。网络传输和存储根目录可注入，测试无需调用真实站点。

SharedPreferences 保存配置、分组、完整阅读记录及任务索引；FlutterSecureStorage 保存登录 token；应用支持目录保存离线章节；临时目录保存可清理的阅读缓存。后续在导入旧库和任务规模增长时评估 SQLite，避免第一版维护两套重复索引。

## 后续里程碑与验收

2026-10-18：第一版已验收；当前六批功能补齐以 [功能状态](FEATURE_GAPS.md) 和 [分批记录](BATCHES.md) 为准。下面保留长期平台里程碑，已实现项不再代表待办。

1. **核心阅读验证**：在真实安卓设备检查首页→搜索→详情→阅读、登录→收藏，以及下载后飞行模式阅读；检查长图内存与快翻、协议参数和图片格式。
2. **安卓下载增强**：任务队列、取消/删除、通知、后台执行、进程终止后恢复、空间管理；明确前台服务/WorkManager 的平台行为。
3. **功能补齐**：分类/榜单、云端历史、收藏夹、评论、注册和签到，按原 API 的真实响应逐项增加 fixture。
4. **数据与网络兼容**：旧 SQLite/下载目录只读导入、可回滚迁移；连接诊断、图片线路切换、必要的原生网络扩展。
5. **桌面与发行**：Windows 构建、键盘/鼠标与窗口适配；Linux/macOS runner；超分插件、NAS、签名和安装包发行。

未迁移的功能保持明确标记，不使用假按钮或演示数据冒充完成。

