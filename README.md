# 拾光号 iOS 启动器 v1.6（三按钮 · 本地端口修复版）

## 首页功能
首页只有三个主要按钮：**导入美化包、清除美化包、进入游戏**。不再显示官网、下载美化包、导入配置或游戏服务器信息。

**美化包就是游戏资源包**，与游戏共用同一套导入/清除逻辑。进入游戏会自动使用资源包中的优先入口（`Client.swf`、`Main.swf` 等），无需手动选择。

## 导入方式（解决此前文件选不了的问题）
1. 点「导入美化包」→「从文件 App 选择」；改用 UIKit 的 **UIDocumentPicker（asCopy=true）**，接受通用文件，不提前限制 `.srom` 自定义类型；选中后再由 App 检查扩展名和文件头。支持 `.srom`、`.zip`。
2. 如果文件选择器仍无法选中 `.srom`：在系统「文件」App 找到资源包，复制到「我的 iPad/iPhone → 拾光号启动器」共享文件夹，然后点「导入美化包」→「从拾光号共享文件夹导入」→ 选中该文件。
3. 也可以在「文件」App 中对 `.srom` 使用共享/打开方式，选择「拾光号启动器」（若系统提供该动作）。应用增加了 `.onOpenURL` 接收入口。

导入过程：从系统文件提供器复制到私有沙盒 → 检查 ZIP 文件头 → 解压到独立临时目录 → 搜索游戏 SWF 入口 → 成功后替换旧版本（失败时保留旧版本）。如果美化包并不是 ZIP 格式，即使扩展名叫 `.srom` 也不能凭空解压：现在会显示具体文件头十六进制，而不是静默失败；需要提供实际 `.srom` 样本才能支持其专有格式。

清除美化包会删除 App 沙盒内已安装的资源，并禁用「进入游戏」，但不主动删除用户在「文件」App 共享文件夹里的原始包。导入前后尽量预留足够空间（复制、解压可能同时占空间）。

## 构建和部署
将 ZIP **解压后**覆盖原 GitHub 仓库文件（保留 `.git`），包含 `.github`、`Sources`、`Resources`、`ShiguangLauncher.xcodeproj`；GitHub Desktop → Commit to main → Push origin。然后到 GitHub Actions 手动运行 **Build unsigned iOS IPA**，在 Summary 的 Artifacts 里下载新的 IPA。

iOS/iPadOS 最低要求：16.0。未签名 IPA 仍需要自行签名安装。保留原 Bundle ID `cn.shiguanghao.launcher`，尽量覆盖安装而非卸载，以免旧资源丢失。

## 验证边界
已完成项目静态检查和 Swift 语法解析；当前运行环境没有 macOS/Xcode/iPad，也没有收到用户的实际 `.srom` 文件，因此**尚未完成 iOS 编译及真机/实际资源包验证**。如果导入仍失败，请提供应用里显示的完整错误文字，以及一个真实的 `.srom` 文件样本；如果只看到不可选灰色文件，请使用第 2 种共享文件夹导入。

内置 Ruffle 和既有本地服务器逻辑保留，GameSocketBridge 中的服务器地址未更改；按钮“清除美化包”不会删除 Ruffle 或 App 自身。


## v1.4：修复导入后游戏无法显示

基于实际提供的 `NieoData/index.html` 与 `assets/index.js` 检查，游戏网页通过 React 动态创建 `application/x-shockwave-flash` 类型的 `Client.swf` `<object>`，并加载 `assets/nieo_wasm_core_bg.wasm` 处理连接。iOS 的 WKWebView 不支持原生 Flash；v1.3 在资源包已有 `index.html` 时没有插入 Ruffle。

本版在**本地 HTTP 服务返回资源包的 `index.html` 时**自动注入 Ruffle，不修改或覆盖你导入的游戏资源文件。`/ruffle/` 映射到 App 内置 Ruffle；启用 polyfill 以接管页面动态创建的 Flash `<object>`；并在已有代理中添加对预设游戏服务器的 Socket 映射。原来的 `index.js`、WASM 通信逻辑保留。

WebView 新增网页脚本错误提示，方便后续排查资源缺失、WebAssembly 初始化或服务器连接问题。请使用 `NieoData` 目录完整的 `.srom` 测试；缺少 `assets/nieo_wasm_core_bg.wasm` 时仍不能进入游戏。此版没有在真机或 macOS Xcode 上编译验证。

仅供你有权使用的游戏资源和服务器环境。


## v1.6：修复 WKWebView「不允许使用受限制的网络端口」

根据实机报错与 v1.4 代码检查，原本本地 HTTP 服务使用 `NWListener(..., on: .any)` 随机端口，并且可能在端口进入 `.ready` 前就生成 WebView 地址；iOS WebKit 会拦截部分端口。v1.6 将本地 HTTP 服务限定为 `127.0.0.1` 上的安全端口 `18765`–`18769`，依次尝试绑定，只有服务进入 `.ready` 状态后才返回加载 URL。若全部端口不可用，将向用户报告具体错误，不再直接黑屏。

WebView 导航错误提示现在会包含 WebKit 错误代码、失败地址，以便继续定位 `index.html`、Ruffle 或服务器连接阶段的问题。Socket 桥接仍在原端口 `32973`，游戏资源本身未修改，现有三按钮首页和图标保持不变。

**验证范围**：本地静态检查及 Swift 语法解析；未在 iOS 真机/Xcode 上运行。若 v1.6 仍然黑屏，请发送屏幕底部的错误全文（特别是请求地址和错误代码），以分辨是被拦截端口、HTTP 资源缺失，还是游戏内部脚本/网络通信失败。无需再次清除或导入已安装的资源包；优先用相同签名覆盖安装。


## v1.6：修复本地启动 `Network.NWError 22 – Invalid argument`

真机 v1.5 截图显示 `启动失败：未能完成操作。(Network.NWError 错误 22 – Invalid argument)`。这发生在游戏网页显示之前，和 `.srom` 解压是否成功无关。

静态审查确认 **两个** Listener (`GameServer.swift` HTTP 和 `GameSocketBridge.swift` WebSocket) 都设置了 `parameters.requiredLocalEndpoint = .hostPort(..., port: P)`，同时又以 `NWListener(using: parameters, on: P)` 指定端口。这样的重复配置可能导致框架构建监听器时抛出 `EINVAL`。本次同时移除两个 `requiredLocalEndpoint`，改用 `parameters.requiredInterfaceType = .loopback`，端口只在 `on:` 中指定，仍仅允许本机回环服务。

另外修复 WebSocket 代理状态跨线程读取，并将代理初始化失败/等待错误直接反馈到游戏启动页，便于区分后续是 HTTP、WebSocket 还是 WebView/Flash 的问题。保留原有游戏数据路径、`.srom` 导入能力、首页三个按钮、图标及 GitHub Actions 配置。

**注意**：该补丁已通过源码语法与结构静态检查，但没有在 macOS/Xcode 编译或 iPad 真机运行，不能保证下一阶段的 Flash/网络功能一定正常。请尽量覆盖安装而非卸载旧版，避免删除 Application Support 内已导入的资源。
