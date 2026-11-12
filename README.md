# 拾光号 iOS 启动器正式版 1.07

- Version: 1.0.7
- Build: 127
- Bundle ID: `cn.shiguanghao.launcher`
- Base: `release/shiguang-1.0.6-b125-ui-delta-srom`

## 1.07 更新

- 游戏服务器更新为 `202.189.22.79:22973`。
- 登录时处理资源包 `ip.txt`：替换已知旧 IP，避免继续连接旧服务器。
- 资源校验根据 `config/dll.xml` 的 `item path` 动态识别核心 SWF。
- 资源校验根据 `assets/index.js` 动态识别实际 WASM 路径；不再要求独立的 `nieo_wasm_core_bg.js`。
- 兼容旧版 Nieo 命名和 0.18.0 资源包的 SG 命名。
- 保留 Build125 的 Ruffle、ZIP/SROM 导入、增量更新、资源缓存、虚拟鼠标、精准触摸、键盘、NoNo、画质和帧率功能。

## 核心与启动器边界

IPA 仅负责启动器和运行环境；游戏核心、WASM、JS、Client.swf、PetFightDLL、地图及其他游戏资源仍由用户导入的 SROM 提供。本版本不替换或重打包任何游戏资源。

## 图标说明

新拾光号 App 图标已正式集成，使用用户提供的完整 1024×1024 PNG，由 Xcode 自动生成各设备图标尺寸。

## 验证边界

静态资源校验不代表服务器可达，也不代表登录、战斗、基地或 NoNo 已完成真机测试。新版外来 SGCore 的活动资源兼容性仍单独验证。
