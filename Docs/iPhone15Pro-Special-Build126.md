# 拾光号 · iPhone 15 Pro 专用版 Build 126

- 基于正式 1.06 Build 125，独立 Bundle ID `cn.shiguanghao.launcher.special`，名称「拾光号专用版」。不修改正式版代码或应用数据。
- **必须重新导入 .srom 资源包**：独立 Bundle ID 意味着独立沙盒，不能自动看到正式版的游戏文件。
- 默认「省电」画质、30 FPS rAF 调度上限、兼容性省资源模式开启（Ruffle 最终 quality=low），仍保持 Flash 原始逻辑帧率。
- 加入 Ruffle 渲染后端对照：自动 GPU（默认）、WebGL、Canvas。旧版曾出现强制 WebGL 卡地图，所以不默认强制 WebGL；Canvas 仅诊断，可能卡顿且不完整。
- 记录进游戏时和 WebContent 终止时的系统、热状态、省电状态、物理内存、后端偏好、帧率和持续时间；记录宿主的内存警告，**这些不能证明 WebContent 自身的内存峰值**。
- 保留已有 NoNo、精准鼠标、基地网络、签到、单字体、增量更新、补丁管理、导出 diagnostics.txt 等正式版功能。
- **证书权限**：截图中的可开启权限不等于最终签名的 entitlement。此 IPA 为未签名；专用版不默认注入 `com.apple.developer.kernel.increased-memory-limit` 或 `com.apple.developer.kernel.extended-virtual-addressing`，以免签名工具/描述文件未授权导致无法安装。这些应用级权限也不能保证独立的 WebKit WebContent 进程获更高内存额度。
- 真机对照：相同 .srom，先自动 GPU 打开背包三次；再（如必要）切 WebGL 对照，如果卡地图立即切回自动；最后再试 Canvas 兜底。每种情况保存日志和同时间的 `JetsamEvent`/`WebKit.WebContent` .ips 报告。
- 15 Pro 专用版仅供实验，不是已经验证的修复。未签名 IPA 使用你自己的签名工具签名；签名后可用 Mac `codesign -d --entitlements :- Payload/ShiguangLauncher.app` 查看真正启用的权限。
