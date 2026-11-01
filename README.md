# 拾光号 iOS 启动器 · 1.1 修复版

Xcode 工程支持 iPhone/iPad（iOS 16 及以上）。用户在应用中导入 ZIP 格式的 .srom 资源包；解压成功并找到入口 SWF 后才替换旧资源。游戏服务器地址由启动器独立配置在 GameSocketBridge.swift：103.91.210.16:22973，不写入也不修改用户的资源包。

针对「拾光号-美化整合包-20261031.srom」，启动器识别 NieoData/Client.swf，并优先打开同目录的 index.html。该网页加载包内的 assets/index.js 与 nieo_wasm_core_bg.wasm，资源通过仅绑定 127.0.0.1 的应用内 HTTP 服务提供。启动器还在 127.0.0.1:32973 提供 WebSocket 转 TCP 通道，目标是上述游戏服务器。若包中没有网页入口，则使用内置 Ruffle 页面加载所选 SWF。

## 构建

1. 用完整 Xcode 打开 ShiguangLauncher.xcodeproj。
2. 等待 Xcode 下载 Swift Package Manager 依赖 ZIPFoundation 0.9.20。
3. 在 Signing & Capabilities 选择自己的开发团队；如标识符冲突，修改 Bundle Identifier。
4. 在 iOS 16+ 的 iPhone 或 iPad 上运行，导入当前资源包后点「启动游戏」。

Ruffle 许可证位于 Resources/Ruffle。

## 验证边界

该 Mac 未安装完整 Xcode，尚未编译、签名或真机运行。WebSocket 转 TCP 是依据资源包中的本机连接配置和网页脚本推断的适配方式；没有实际登录流量，尚不能确认协议完全匹配，也不能保证游戏已经可玩。真机登录后如有错误，需要根据连接日志继续适配。

## 无本机 Xcode 的构建路线

工程包含 .github/workflows/ios-unsigned.yml。把 ShiguangLauncher 目录中的所有文件（含 .github 隐藏目录）放到 GitHub 仓库根目录后，在 Actions 中手动运行 “Build unsigned iOS IPA”。下载构建产物 ShiguangLauncher-unsigned-ipa，再解压得到未签名 IPA。未签名 IPA 不能直接安装；可在这台 Mac 上用 Sideloadly 的 Apple ID Sideload 模式给自己的设备签名安装。资源包不会上传到 GitHub，也不会打进 IPA。首次运行该工作流如编译失败，请保存完整日志以便修复。

## 1.1 修复说明（2026-11-01）

1. 首页不再显示游戏服务器地址（服务端连接配置仍保留在 `GameSocketBridge.swift` 中）。
2. 为 iPad/iPhone 添加原生 `UILaunchScreen` 配置；首页采用自适应的全宽背景和居中内容区，游戏 WKWebView 禁止自动内容缩进。**如果游戏 SWF/资源包内部强制固定宽高比，游戏画面仍可能出现黑边，需要拿实际 .srom 进一步诊断，不能保证所有游戏场景拉伸铺满。**
3. 注册 `cn.shiguanghao.srom` 文件类型，并兼容 `.zip` 和被文件提供器归类为通用数据的 `.srom`；在开始后台解压前取得安全范围访问权限。若仍无法选择，请确认文件在“文件”应用中已完整下载到本机、文件名以 `.srom` 结尾。
4. 新增 1024px 星空飞船应用图标和 iPhone/iPad 图标尺寸，配置在 `Resources/Assets.xcassets`，首页也显示该图标。

### 将修复版更新到 GitHub

先把 ZIP 解压，在 GitHub 仓库上传**压缩包内的全部文件和目录**，覆盖原有的 `Sources/`、`Resources/Info.plist`、`ShiguangLauncher.xcodeproj/project.pbxproj`，**并新增** `Resources/Assets.xcassets`。`.github/workflows/ios-unsigned.yml` 保持不变。上传后重新运行 Actions → Build unsigned iOS IPA，再下载新的构建产物。

> 注意：只上传新增图标文件而不更新 `project.pbxproj`，应用图标不会参与编译。
>
> 修复版仍要求 iOS/iPadOS 16 或以上，未修改服务器配置、游戏资源、签名方式。iPad Air 2 如运行 iPadOS 14/15，仍无法安装该版本。
>
> 本地只能检查项目结构、Swift 语法与资源配置；没有 macOS/Xcode 和真机，**尚未验证重新编译及设备表现**。若 Actions 失败，请检查具体失败日志。
