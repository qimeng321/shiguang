# 拾光号 iOS 启动器

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
