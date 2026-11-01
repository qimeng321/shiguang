# 拾光号 v2.6 — 真全屏游戏 / 精简启动体验

根据用户 v2.5 真机截图与原网页打包的 React `index.js`：
- 原网页 Flash object 属性为 `width=960 height=560`，并有 `scale=noScale` Flash 参数。
- v2.5 CSS 使用 `min()` 保持 960:560 比例，仍可能留下黑边或矩形边界。
- Ruffle 仍配置 `unmuteOverlay="visible"`，因而显示“点击取消静音”；默认 `splashScreen` 会出现蓝色 Ruffle Logo/进度条。

v2.6 修改：
1. Ruffle `unmuteOverlay="hidden"`，`splashScreen=false`，`preloader=false`，去除两种内置启动遮罩（Flash 尚未就绪时只显示黑色背景，不意味着跳过真实加载）。
2. 原网页/游戏元素 CSS 强制 100vw × 100dvh，无边距、无最大尺寸/原始比例限制。
3. Ruffle `scale="exactfit"` + `forceScale=true`，覆盖网页原来的 `noScale`，确保 Flash 内容而不只是外层播放器铺满可用区域。因不维持原始宽高比，可能稍有变形；不裁切游戏按钮。
4. 左上角返回、右上角刷新/清理缓存、左下角诊断入口均保留，资源、登录设置、WebSocket 与 PVM 实验保持原样。
5. 缓存清理只针对 WebKit 内存/磁盘缓存，不会删除 `Application Support/Game` 下的游戏资源。

注意：v2.5 日志仍显示 PVM 的 version.swf 两次 GET 后未进入登录；v2.6 仅修复 UI 与显示，不保证登录问题解决。若画面拉伸或按钮触控映射仍有问题，提供横屏截图和 diagnostics.txt。

# 拾光号 v2.5 — 全屏游戏与右上角网页控制

参考用户提供的 xin计划 IPA 实际内容，确认其 Flutter + flutter_inappwebview_ios（WKWebView）+ Ruffle 架构。本项目保持 SwiftUI + WKWebView + Ruffle，不必为了界面重写 Flutter。

- 游戏全屏页面：隐藏状态栏，沉浸式黑色背景；按 960:560 比例自适应 WebView 内 Flash 对象，不拉伸/裁切画面。
- 左上角：返回启动器。右上角：圆形「刷新游戏」「清理网页缓存」悬浮按钮；左下角小波形图标可展开原有调试状态，不再长期遮挡画面。
- 刷新游戏：重建 WKWebView，重启 Flash 页面；本地服务器与 Application Support/Game 资源不受影响。
- 清理缓存：二次确认后仅删除 WebKit 的 DiskCache/MemoryCache，然后重启页面；**不删除 cookies、localStorage、已导入的 .srom、美化包、诊断日志**。不会恢复因服务器或 SWF 兼容性导致的卡 Logo。
- v2.4 真机日志仍只有两次 version.swf GET，头部分段传输未解决此启动阻塞；该兼容性问题仍在排查中。

# 拾光号 v2.4：PVM 分阶段传输实验

根据 v2.3 真机日志（version.swf 前缀 4B 50 04 D4 00 00 78 DA；读取版本文件两次后停止），结合游戏的 PVM_Loader.as 源码，确认表项数为 0 并非必然损坏。实验性调整版本文件的本地 HTTP 传输：前6字节单独发送，延迟120毫秒后继续发送剩余数据，使 Ruffle URLStream 更可能触发增量进度回调。不改变文件字节内容，其他 HTTP 资源不受影响。增加版本 URL 请求阶段分类（不记录实际参数）、第三次 version.swf 请求识别，并修正 PVM 文件头误报。

**这是针对性实验而非已验证的兼容性修复**。覆盖安装测试，进入游戏后停留至少25秒，再分享 diagnostics.txt。此应用不需要改动或重新导入既有 .srom 资源。

# v2.3：PVM 版本加载专项诊断

本版保留 v2.2 已正常运作的资源导入、Ruffle、HTTP 与 WebSocket 机制，只增加 `version.swf` 文件头检查、TCP 传输完成情况、5/15 秒 PVM 阶段提示及 Ruffle 5/20 秒状态观察。**真机测试时在游戏界面保持至少 25 秒**，再提交 `diagnostics.txt`。本版仍是诊断版，不能保证已能进入登录界面。

# 拾光号 v2.2：PVM 卡 Logo 专项诊断与自动构建

- 以 v2.1 代码为基础；导入、美化包路径、Ruffle 和游戏服务器连接逻辑保持不变。
- 记录 Flash trace 输出，并避免在 WKWebView 文档根元素尚未创建时挂载观察器。
- 记录 version.swf 的真实 GET 和是否继续加载 DLL/登录模块。
- 推送到 main 分支后由 GitHub Actions 自动编译并上传未签名 IPA。
- 仍需 iPad 真机验证；不要在日志中分享账号、密码或令牌。

# 拾光号 iOS 启动器 v2.1 — 启动画面停滞专项诊断

基于 v2.0 已确认资源路径与 Ruffle 渲染正常，本版**不调整已成功的 `.srom` 导入、资源路径和游戏渲染代码**，只补充定位后续启动阶段所需的日志。

- 对 `config/`、`resource/`、`login/`、SWF 和 XML 请求记录 GET/HEAD、HTTP 状态、响应字节数；最多 300 项。
- 网页启动后用 `HEAD` 检查 `config/doorConfig.xml`、`resource/main_resource.swf`、`config/ServerR.xml`、`login/Login.swf`、`version.swf`。注意 **HEAD 测试不代表游戏确实发起了 GET**。
- 收集前 60 条相关 Ruffle/AVM2 console 警告错误（不采集明文网络通信内容）。
- 记录游戏 WebSocket 代理接入和远端 TCP 连接成功/失败（不采集账号或游戏封包内容）。
- 保留三按钮页面、图标、文件共享、导入逻辑、固定本地端口和 GitHub Actions 工作流。

## 安装与查看

用原签名和 Bundle ID 覆盖安装，不要清除美化包；进入游戏并观察是否从 Logo 页面继续，之后读取“文件 → 我的 iPad → 拾光号启动器 → diagnostics.txt”。

重点区分：

1. `HEAD /config/doorConfig.xml → 200` 只表示文件可访问；需另外出现 `GET /config/doorConfig.xml` 才说明 Flash 发起了请求。
2. 若 `GET /config/doorConfig.xml → 404`，则需要修复实际资源缺失或游戏 URL；不能简单依赖 Ruffle。
3. 若所有资源都返回 200，但仍卡在 Logo，需检查 Ruffle AVM2 错误、网络连接或游戏自身运行逻辑。

此版本是诊断版本，**尚未在 Xcode 或 iPad 真机验证最终能进入登录界面**。

---

# 拾光号 iOS 启动器 v2.0 — 游戏入口路径修复

这次重点修复 v1.9 日志中出现的路径截取异常：`rt/Game/NieoData/Client.swf` 可能来自绝对路径按字符长度截取造成的错误，而非 ZIP 中的真实位置。

- 扫描资源时使用 `FileManager.enumerator(atPath:)`，直接读取系统给出的**相对路径**，不再使用 `dropFirst(root.path.count + 1)`。
- 只接受实存、可读的 SWF 文件作为启动入口。
- 暂存解压完成后检查入口；安装后再次验证真实入口，否则不报告导入成功。
- 安装新资源时保留旧目录备份直到最终验证成功。
- 诊断日志记录临时目录与最终已验证的入口文件路径。
- 保留原有三个按钮、iPad 布局、Ruffle、HTTP/Socket 服务、共享文件夹及 GitHub Actions。

**注意**：v1.9 最新日志显示用户已清除美化包，因此本次升级后需要重新导入一次 `.srom`。请优先使用相同签名和 Bundle ID 覆盖安装，勿先卸载 App。

本项目在 Linux 环境执行 Swift 源码语法解析和文件一致性检查，不等同于 macOS Xcode 编译或 iPad 真机验证。

# 拾光号 iOS 启动器 v1.9 — 依据 v1.8 真机日志修复“假成功黑屏”

2026-11-01 的 v1.8 `diagnostics.txt` 表明：本地 HTTP 18765 端口已运行、只有 GET /index.html 请求；未出现 Ruffle 或 SWF 请求；且 SWF 检查显示 `[缺失] Client.swf`。

## 修复点

- .srom 解压完成后**重新扫描最终安装路径**，不再使用 staging 临时目录中的 SWF 清单直接声称“导入成功”。
- 首页检测到 SWF 入口已消失时重新扫描，并在找不到真实 SWF 时禁用“进入游戏”，显示资源异常状态。
- 优先选择有同目录 index.html 的 SWF 入口；资源检查新增绝对路径、同级文件与其他 index.html 的诊断。
- 只允许在 SWF 入口确实存在时启动游戏；错误信息直接显示在 App 页面，并写入 `Documents/diagnostics.txt`。
- 资源服务对错误的 `entry` 不再返回可能看不清的纯文本，改成醒目的 `HTTP 400` HTML 错误页；同时记下 HTTP 200/400 结果，区分“网页打开”和“游戏真正打开”。
- WKWebView 加入已完成网页的 DOM/脚本状态日志，便于判断网页是正常游戏还是错误文本。
- 保留 v1.8 的三按钮首页、App 图标、Files Import 文件夹、共享诊断日志、原来的 Application Support/Game 资源路径、Ruffle、HTTP Range 和网络桥接。

## 更新/验证

1. 解压 ZIP 覆盖 GitHub Desktop 中的本地工程，保留 `.git`；**Commit to main → Push origin**。
2. GitHub Actions 重新执行 `Build unsigned iOS IPA`，在 Artifacts 下载构建结果。
3. 保持旧版应用 Bundle ID 与签名方式，覆盖安装以保留已保存资源；不要卸载或主动清除美化包。
4. 打开首页，检查资源诊断：如入口存在则点击进入游戏；如提示缺失，先分享 `diagnostics.txt`，避免重新导入浪费存储。
5. 若继续黑屏，提供最新 `diagnostics.txt`，查看 `HTTP 200`、`HTTP 400`、`页面诊断` 等信息。

**限制**：现有日志指向实际文件未找到及错误页未被区分，并未证明 `.srom` 中的网页资源完整，也尚不能证明联网游戏可运行。当前环境无 Xcode/iPad，已做基础语法和工程静态检查，但不能保证真机运行；不要清理 2.88GB 旧资源，先看新日志。
