# v3.5 — 自适应底部居中输入栏（优先保持 v3.4 输入兼容）

2026-11-01 真机截图验证 v3.4 白色输入栏能够输入，但右上角遮挡游戏 Logo 和系统按钮。v3.5 保留同一个 Ruffle 原生输入框及上一版的字符事件桥接，只修改响应式布局：横屏优先在游戏下方的黑色留白居中放置；软键盘弹出导致 visualViewport 变小时，输入栏移动到键盘上方。宽度受屏幕限制，最大 420 CSS px，最小适配窄屏，左右保留边距；游戏本身仍保持原 12:7 比例。不会因键盘弹出缩小 Flash 画布或覆盖右上角刷新/清理按钮。

已附带的 v3.4 网络预检仍然保留。2026-11-01 日志：[网络预检] 线上 TCP 可连接；HTTP /login/Login.swf 成功；启动22秒仍未观测到 Flash 到本地 WebSocket 代理的连接；用户输入后 /ip.txt 404。仅凭这些还不能宣称登录成功；本版本不凭猜测伪造 ip.txt 内容。若登录仍不通，需进一步核对 Windows 微端实际 ip.txt 内容或等待新版详细日志。

覆盖安装，不要卸载以免清空此前导入的资源。依次点击 Flash 登录框和游戏画面**下方居中的浅色输入栏**，测键盘和文字；观察软键盘弹出后输入栏是否自动浮在键盘上方。请继续导出 diagnostics.txt，重点查找「输入栏自适应位置」和「[登录网络]」相关日志。

# v3.4 — iPad 真实触摸键盘与登录网络探针（仍待真机验证）

根据最新测试，v3.3 已可进入米米号登录窗口，但用户看到提示后转圈，iPad 键盘仍闪退。Windows 微端 config.json 中线上服务器 login/game 均为 103.91.210.16:22973；IPA 使用相同目标。仅凭服务器地址相同不能证明网络连接成功。

v3.4 用可直接触摸的白色 HTML 输入栏代替对 Ruffle 隐藏输入框的程序焦点模拟。先点击 Flash 的账号（或密码）栏，再直接点击游戏画面右上角的白色栏，利用真实用户点击让 iPadOS 弹出键盘。它是 Ruffle 自己的同一个 #virtual-keyboard 元素。原生输入事件经过唯一桥接，不向 Ruffle 重复转发普通按键；处理退格及输入法组合。不会记录任何输入字符、密码或账号。本方案需要 iPad 真机测试是否能正确写入 Flash。

新增对线上 TCP 服务器的 8 秒可达性预检，不发送用户数据，另外记录 Ruffle 本地 WebSocket 握手和真实 TCP 双向传输；明确区分可连通与实际登录验证。再次在 Ruffle load options 指定 SocketProxy，包含线上服务器地址和本地主机回退匹配。保持原 .srom、Ruffle 0.7.1 和 PVM/ByteLoader 补丁不变，未擅自补造 ip.txt。

操作：直接覆盖升级 IPA，别卸载旧版。点 Flash 账号框，再点游戏画面右上角白色输入栏，输入测试字符，检查是否重复；密码同理。若仍转圈，请提交新版 diagnostics.txt，关注 [网络预检] 和 [登录网络]。

# v3.3 — iPad 键盘去重与登录链路诊断（需真机验证）

2026-11-01 日志中 Client.swf、version.swf、NieoCore.swf、Login.swf 均 HTTP 200，但尚无游戏服务器连接成功的证据；ip.txt 404 与登录转圈的因果关系未经确认。

- 键盘触发只处理 click，取消 touchend + click 双次调用；不再对已经聚焦的 Ruffle 输入框 blur/focus。收起/弹出键盘引起的视口高度收缩不改变游戏原有尺寸；旋转/分屏仍适配。
- 新增按键事件种类的计数诊断（不记录字符、账户、密码）。
- 登录新增本地 WebSocket 握手、远端 TCP 连接、首个双向数据包字节数（不记录负载）的阶段日志。如果进入游戏22秒仍没有 Flash 连接本地代理，记录明确诊断。
- 不修改或清除 .srom，不构造假的 ip.txt，不更换 Ruffle 0.7.1 或 PVM / ByteLoader 补丁。

覆盖安装测试：依次点 Flash 账号输入框和右上角 ⌨，测试单个英文字符、删除、中文与密码输入，然后尝试登录。导出 diagnostics.txt 并查看 [登录网络] 与 键盘事件计数。编译通过不代表游戏登录已修好。

# v3.2 — iPad 触屏键盘兼容性修复

v3.1 已通过用户真机验证能进入登录页面，但点击 Flash 输入框不能调出 iPad 系统键盘。Ruffle 0.7.1 `web/packages/core/src/internal/ui/static-styles.css` 把 `#virtual-keyboard` 放在 `top:-100px;width:1px;height:1px;opacity:0`，在 iOS 26.4 及之后的 WebKit 中容易无法触发系统软键盘。Ruffle 官方亦有 iOS 文本输入焦点问题报告 #23509、#23675。

修复：保留原 v3.1 Ruffle 0.7.1、PVM + ByteLoader 双补丁、`/__micro/game.html` 直启、HTTP 和 WS/TCP 代理。创建右上角第三个原生网页触摸键盘按钮（位于刷新、清缓存下方），通过用户实际触摸事件同步聚焦 Ruffle 自己的 Shadow DOM `#virtual-keyboard`。将该输入框移回画面内且赋予非零大小、不完全透明，解决离屏隐藏输入拒绝键盘的问题。Ruffle 自带的 `virtualKeyboardInput()` 负责把实际键入文字转为 Flash 键盘事件；另加小型“退格/回车”操作，兼容部分触屏键盘退格键。使用真实事件处理器而非 Swift 异步 WebView JavaScript 调用，以避免失去 iOS 用户手势激活上下文。

**使用方法：先点击 Flash 账号/密码输入框，再点右上角蓝色 ⌨ 按钮**，在系统键盘输入文字。键盘按钮只补足系统唤起，不会自己定位游戏内输入目标。不会记录账号、密码或键入文本，也不会修改美化包。仍需 iPad 真机测试键盘是否弹出及文字是否写入 Flash；编译成功不能视为输入修复验证。

# v3.0 — 针对 Ruffle URLStream 的 Flash PVM 事件兼容补丁

从真实 Client.as / ByteLoader.as / PVM_Loader.as 和 Ruffle v0.7.1 代码交叉分析，发现 Ruffle URLStream 借助 URLLoader 完整下载后一次性分发 PROGRESS/COMPLETE，而 URLLoader.close() 是占位实现。原始 PVM 在 PROGRESS 内 close() 并 reload，先前旧请求可能继续发 COMPLETE，干扰版本管理器。v2.9 改为 TCP FIN 依旧无法解决。Windows 微端含 Ruffle 桌面执行路径及 Windows Flash ActiveX 路径，单纯认为它只用 Ruffle 并不准确。

v3.0：采用 FFDec 26.4.0 **重编译用户提供的原版 Client.swf 的 PVM_Loader._onComplete 方法**，只在已经载入正确版本头且有实际 body 数据时处理 Event.COMPLETE，忽略旧请求在 reload 时的遗留完成事件。原版 SWF SHA256 为 `d64a9e3af813324f6e1f9844e74eee16dee5d76a4c8a26c417585467a3c3e59f`；编译后验证 PVM 类包含此检查。为不修改/复制 2.88GB 资源，项目只存储 **2208 字符压缩二进制差异补丁**；浏览器 SHA256 校验并仅在内存里解压/apply，构建一个有效 FWS 交给 Ruffle 的 DataLoadOptions `data` 入口。指纹不符、浏览器不支持或解码异常时自动使用原版。原始 .srom 永远不改动。v2.9 的屏幕自动适配、刷新/缓存按钮、直启页和 WebSocket->TCP 代理全部保留。

我们已在 Node 22 上模拟 WebKit 流程，验证差异补丁重构出的解压 SWF 与 FFDec 真实导出的目标 SWF **字节完全一致**。但这仍是兼容性修复假说，未经 iPad 真机验证。请安装后查看 diagnostics.txt 是否出现“已对原版 Client.swf 应用 PVM 事件兼容补丁”、是否在单次启动内出现**第三次 GET /version.swf**，以及是否 GET /login/Login.swf。请勿卸载应用或清空现有美化包。

# v2.9 — iPad 自适应布局 + Windows 微端式直启 + TCP 正常关连接

对照 Windows 1.2.5 微端、Client.as、PVM_Loader.as 和 ByteLoader.as：Windows 使用 Ruffle 原生桌面运行时直接加载 Client.swf，而原 iOS 使用 React/index.js/WASM 启动；游戏的 PVM 使用 Flash URLStream.PROGRESS 和 COMPLETE 事件。v2.8 仍停在第二次 version.swf 请求后。Windows 包内的 version.swf 前6字节为 4B5004D40000，后续 zlib 压缩体可以解压至约 50 KB，头表项0不代表损坏。

本版在原有本地 HTTP 服务增加 `/__micro/game.html`，直接创建 Ruffle 播放器运行 Client.swf，继续由原 WS→TCP 代理提供游戏 Socket；不启动 React 网页。基于浏览器 visualViewport 的实际宽高和 960:560 画面比例计算最佳等比最大化尺寸，水平垂直居中，支持旋转、分屏和窗口尺寸变化。取消不稳定的6字节/120ms HTTP 分段实验。所有 HTTP 正常发送完毕后使用 Network.framework `.finalMessage` 发送 TCP FIN，避免过早 `connection.cancel()` 使 URLStream 收不到正确事件，2秒后释放连接。PVM FIN 日志保留。

**注意：修复假说仍需 iPad 真机验证；本次改变了 Flash 启动流程和 HTTP 结束方式，但 Xcode 编译成功并不保证登录成功。** 更新时不卸载旧版，不清理 .srom，游戏界面保持至少25秒，提交 diagnostics.txt，重点检查 `微端式直启`、`TCP FIN`、第三次 GET /version.swf 和登录模块 GET。

# v2.8 — 游戏保持比例并水平/垂直居中

v2.7 的真机截图显示 Ruffle 0.7.1 可渲染 960×560 的游戏背景，但舞台仍固定左上角。根因之一是 v2.6 注入样式强制 `position:fixed;left:0;top:0`，破坏了 React 原本的 flex 居中定位。虽然 v2.7 试图进行全屏 exactfit，但游戏实际内部保持固定区域。

v2.8 恢复居中策略：`#root` 与容器使用 Flex 居中；另对 Ruffle polyfill 的宿主元素使用 `left:50vw;top:50dvh;transform:translate(-50%,-50%)`，并按照 Flash 原始 960:560（12:7）比例计算自适应尺寸，画面完整优先，不裁切也不拉伸变形。Ruffle 改为 `showAll`，继续隐藏 splash 与取消静音提示。8 秒时增加 viewport 与舞台实际 bounding rect 诊断，便于发现仍有居中偏差。

当前游戏登录仍受 PVM 后续加载问题影响：v2.7 日志确认 Ruffle 0.7.1 仍只有两次 version.swf GET，本次不修改通信、资源或引擎版本以降低回归风险。

# v2.7 — Ruffle 0.7.1 引擎对齐实验

对用户提供的「拾光号微端-1.2.5-安装包.exe」静态解包确认：Windows 微端用 C# Windows Forms 的 AxClient.exe + 原生 Ruffle Rust x64 引擎 GameEngine.exe，后者 2026-10-29 构建（Ruffle 0.7.1）；内部客户端 Client.swf 82806 字节、version.swf 20512 字节。iOS v2.6 内置 Ruffle 0.5.0 stable（2026-08-03）。

v2.7 的 GitHub Actions 使用固定的官方发布包 `v0.7.1/ruffle-0.7.1-web-selfhosted.zip`，在 Xcode 编译前覆盖工程自带旧版本 Ruffle 网页核心，附带 `engine-version.txt`，运行时将实际引擎标记写入 diagnostics.txt。保留既有 game HTML、PVM、HTTP、本地 WS/TCP 代理和 UI；**此版只验证 Ruffle Web 升级，暂不改为 Windows 风格专用游戏页面**。Windows 原生版不能直接放进 iOS，但 Web 0.7.1 与它属于同一个 Ruffle 系列。

如果升级后能出现第三次 GET /version.swf 或 /login/Login.swf，说明新版引擎帮助推进了加载；如果仍然卡住，下一步才考虑模仿 Windows 的 /__micro/game.html 直连 Client.swf，以及定位 Ruffle Web URLStream 事件差异。

注意：这是实验性版本；不保证进入登录；使用相同 Bundle ID/签名覆盖安装，不要清除美化资源；测试 25 秒并发送日志。开发者本地仅构建当前仓库内置版本，GitHub Actions 云构建才使用 Ruffle 0.7.1。

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
