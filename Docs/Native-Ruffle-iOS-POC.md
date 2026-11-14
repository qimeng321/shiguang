# iOS 原生 Ruffle 技术验证版（独立 App）

## 目的

用于验证 [madsmtm/ruffle-ios](https://github.com/madsmtm/ruffle-ios) 的原生 Rust + Metal Ruffle 能否在 iPhone / iPad 运行常规 SWF，不替换「拾光号正式版 1.08 Build130」。

## 实现

- 原生代码来自固定上游提交 `c3489324265221ff5089442797be671df14fdcdb`；构建时克隆，不在本仓库引入第三方代码。
- 独立 Bundle ID：`cn.shiguanghao.ruffle.nativeprobe`。与正式版 `cn.shiguanghao.launcher` 不同，可并排安装。
- 保留项目现有 Rust Ruffle Core、UIKit、Metal/wgpu 播放器、SWF 文件选择逻辑；不添加假模拟或伪装成原生的网页 Ruffle。
- 通过 GitHub Actions macOS Intel + Xcode + Rust nightly 构建；输出未签名 IPA 供测试者自行签名。
- 初次验证为简单的本地 SWF 启动、触控、旋转、内存占用及实际闪退情况。

## 不包括

- **没有**把完整拾光号 .srom 导入/解压、动态资源文件路径映射、资源更新或手机 .sgpatch 功能移植到原生项目。
- **没有**把现有的登录、频道、基地 WebSocket/TCP 桥接实现接入原生 Ruffle。
- **没有**宣称这个实验版可完整登录拾光号或修复命运之轮。
- 不是正式版，不应替代当前稳定启动器。

## 测试顺序

1. 保留正式版 1.08 及已导入资源；新 App 的 Bundle ID 独立。
2. 对测试版 IPA 使用自己的证书签名并安装。
3. 在文件 App 中准备一个有合法来源的简单 .swf，通过原生 Ruffle 文件导入/打开。
4. 记录 App 是否启动、是否正常显示、点击和缩放是否正常、切换前后台后是否退出。
5. 若真实 SWF 播放器可用，再专门研究 SROM、网络桥接、核心 SWF 热加载与命运之轮，避免一次改动过大无法定位问题。

## 构建证据与上游

- 上游仓库：https://github.com/madsmtm/ruffle-ios
- 上游声明其本身仍为 work in progress。
- 独立实验分支：https://github.com/qimeng321/shiguang/tree/test/shiguang-ios-native-ruffle-poc

本实验工作流不更改正式版 Swift 工程文件。
