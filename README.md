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
