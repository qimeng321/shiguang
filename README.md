# 拾光号 iOS 启动器 v1.8（v1.7 黑屏修复 + 文件共享及资源诊断）

## 本次合并

- 延续 v1.7 的 Ruffle 注入、`/video.mp4` 遮罩自动跳过、HTTP Range 分段读取、HTTP 端口重试与 WebSocket 桥接。
- 首次启动时自动创建可见的 `Documents/Import/` 和 `Documents/diagnostics.txt`、`Documents/使用说明.txt`，在开启 iOS 文件共享时应显示为 **文件 App → 我的 iPad → 拾光号启动器**。
- 已安装资源仍存放 `Application Support/Game`，不会复制到 Documents；**不会额外占用 2.88GB**，既有存储路径与 Bundle ID 都不变。
- “导入美化包”除了文件选择器，还能读取 Documents 根目录、`Import/`、`Inbox/` 中的 `.srom` 和 `.zip`。
- 关键文件静态检查：SWF 入口、原网页 `index.html`、`assets/index.js`、`assets/nieo_wasm_core_bg.wasm` 以及内置 Ruffle。仅报告检查结果，不修改大文件或干预进入游戏。
- 日志追加：HTTP 服务端口、关键资源请求、404 缺失、网页脚本错误、Ruffle/Flash 状态等。日志上限约 1MB；较早内容轮转到 `diagnostics-previous.txt`。
- 首页三个主要按钮不变：**导入美化包、清除美化包、进入游戏**。不恢复官网、下载美化包和导入配置。

## 更新与验证

1. 解压 ZIP，复制文件和隐藏的 `.github` 目录，覆盖 GitHub Desktop 克隆的仓库（**保留 `.git`**）。
2. **Commit to main → Push origin**；打开 GitHub Actions，执行 `Build unsigned iOS IPA`。成功后在 Artifacts 下载 ZIP 并解压得到 IPA。
3. 用相同 Bundle ID 和签名方式**覆盖安装**，不要先卸载旧版，也不要点“清除美化包”。原已安装美化包应继续保存在私有存储目录。
4. 安装后进入 **文件 → 我的 iPad → 拾光号启动器**，应该看到 `Import`、`diagnostics.txt` 和 `使用说明.txt`。
5. 若进入游戏仍黑屏，退出到启动器后打开 `diagnostics.txt`，查看 `[缺失]`、`HTTP 404`、`网页状态`、`网页错误` 行。可以复制相关错误用于继续排查。

**注意**：资源检查“通过”仅代表关键文件存在，并不证明 `.srom` 内容完全有效或游戏可连接。原有 v1.7 的黑屏处理也仍需真机验证。当前环境无 iOS SDK/Xcode，已做 Swift 语法和项目静态检查，但不能声称已成功编译或在 iPad 上运行。最低 iOS/iPadOS 为 16.0；unsigned IPA 仍需自行签名。仅使用你有权运行的游戏资源。
