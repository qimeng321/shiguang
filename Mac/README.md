# 拾光号 Mac 1.0 · 开发预览版

这是与 iOS/iPadOS 正式版 1.0 并行维护的原生 **macOS** 桌面版本。iOS 工程、IPA 和用户原有 .srom 数据不受影响。

## 技术结构
- `Mac/MacApp.swift`：macOS 12+ 原生 SwiftUI 启动器、Finder 文件选取、独立游戏窗口、标准键盘/鼠标、全屏、日志及缓存操作
- `Mac/Package.swift`：Swift Package Manager 构建描述，ZIPFoundation 0.9.20
- `Sources/GameServer.swift`、`GameSocketBridge.swift`、`LauncherModel.swift`：与 iOS 共用的 Flash 本地资源服务器、Socket 网桥、资源导入/真实进度逻辑
- `Resources/Ruffle` 在 CI 打包时使用已确定的 Ruffle 0.7.1 及附带兼容补丁、简体中文字体
- Mac 沙盒数据保存到 `~/Library/Application Support/ShiguangMac/Game/`，日志在 `~/Documents/拾光号 Mac/diagnostics.txt`
- `.github/workflows/mac-universal.yml` 在 macOS CI 构建 **Intel x86_64 + Apple Silicon arm64** 双架构 Universal binary 并生成 `.dmg` 和 `.app.zip`

## 安装与注意事项
1. 推荐安装 macOS 12 Monterey 或更新版本。2017 款 MacBook Air 官方最高支持 macOS Monterey，可运行 Intel 编译架构（需后续真机验证显卡性能）。
2. 打开 DMG，把拾光号 Mac 拖入 Applications 应用程序。此版本仅作 ad-hoc 签名（**没有 Apple Developer ID 公证**），macOS 可能阻止打开；在系统安全设置中确认可信来源后才能启动。
3. 首次打开选择 `.srom` / `.zip` 资源包；导入进度条由真实复制字节与 ZIP 解压处理量计算；同一资源只需导入一次。
4. 进入游戏后鼠标直接操作；游戏窗口可以缩放、全屏和刷新。原 iPad 触控辅助菜单并未移植到 Mac UI。
5. **构建成功≠真机可玩验证**，特别是 Intel Mac 上的 Ruffle WebGL、WebKit 键盘和登录代理兼容性仍需实测。出错时提供 Mac 版 diagnostics.txt。

## 安全和依赖
源码不内置用户美化包、私服账号、签名证书。Windows 微端程序不能直接在 macOS 运行，因此共享 Ruffle Web 0.7.1 客户端代码。GitHub CI 构建时需要访问 Ruffle 和 Noto 字体的官方发行源。推荐保留 iOS 正式版 1.0 的主线版本不动，Mac 版单独测试。

