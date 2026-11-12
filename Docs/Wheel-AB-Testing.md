# 拾光号 iOS 命运之轮专项 A/B 测试说明

## 目的
对照 Windows Ruffle 正常、iOS Ruffle 在宝箱/下降自动换层后不自动抽卡的问题。正式版 1.07 Build128 不修改。本测试包仍显示 1.07 Build128，但桌面名为「拾光号测试」，Bundle ID 为 cn.shiguanghao.launcher.wheeltest。

## 两个测试包
- stable: Ruffle Web 0.7.1，与正式版引擎相同。
- nightly: Ruffle Web nightly-2026-11-12，固定版本便于可重复验证。
- 两个包使用**同一 Bundle ID**，因此不能同时安装；后装的测试包覆盖前一个，尽量使用同一证书签名，以保留测试 App 内导入的 SROM。
- 测试 App 与正式版 Bundle ID 不同，不能直接使用正式版 App 沙盒中的资源。首次安装测试版需要独立导入 SROM；不要删除正式版。
- 测试包不包含游戏 SWF，未修改 SGCore.swf、WheelChoice_UI.swf、WheelAnimate.swf 或游戏网络协议。

## 建议测试顺序
1. 先安装 stable。保持“均衡画质、帧率不限制”，进入命运之轮；分别验证抽到下降、宝箱、打怪胜利后下一层能否显示抽卡。
2. 每条路径分别导出 diagnostics.txt，备注测试路径、楼层、是否出现卡片以及是否出现等待/闪退。不要在日志中添加账号密码。
3. 用同样签名覆盖安装 nightly，不删除测试 App；重新测试相同路径，再导出日志。
4. 如果 nightly 正常而 stable 异常，优先考虑仅升级 Ruffle；如果两者都异常，对照原生 Flash/电脑 Ruffle，进一步分析 WebKit 时序或宿主网络代理。
5. 不要修改服务器抽奖概率，不要重复发送奖励、挑战或抽卡协议来“强制”修复状态。

## 追踪项与限制
- SWF 已成功送达：WheelChoice_UI.swf、WheelAnimate.swf、map/10036.swf 的本地 HTTP 请求。
- 请求这些文件后开启 32 秒追踪窗口：记录游戏协议上下行**命令号、包长度、结果码**（只记录元信息，不记录用户 ID、登录令牌、负载）。
- 同期采集 WebKit 页面 requestAnimationFrame 的3秒采样量、最大帧间隔、页面可见性与焦点状态；不是 Flash ENTER_FRAME 计数。
- 追踪窗口最多记录200条协议，避免日志无限增长。
- **限制**：HTTP 200不代表 ActionScript 抽卡回调完成；协议日志也不能直接证明 MAP_EFFECT_COMPLETE 触发。若要确认某个 ActionScript 内部回调，需要后续单独的 SWF 事件追踪补丁。
