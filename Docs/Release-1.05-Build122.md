# 拾光号 iOS 正式版 1.05 Build122 修复说明

## 基地无法进入：定位到 Ruffle 最终加载配置
上一版已将服务器下行 GET_ROOM_ADDRES (10002) 的基地地址转换到虚拟端口 22975，并开启本地 WebSocket 32975。但游戏日志证明基地没有建立新的连接。

原因：`window.RufflePlayer.config.socketProxy` 包含 22975，然而真正调用 `player.ruffle().load(options)` 时，`options.socketProxy` 再次被赋值，并遗漏基地路由，覆盖了默认代理映射。Build122 已将 22975→32975 写入最终 per-player `options.socketProxy`；CI 加入回归检查。

同时新增 GameProtocolFramer，先重组完整 TCP 协议消息再处理服务器地址，以兼容分包与粘包。为基地请求/响应添加有限度的日志，不记录账号或数据内容。

## 字体偏下
支持三种中文后备字体位置：原始、上移（+110/1000 em）、再上移（+170/1000 em），默认上移。只影响 Ruffle 设备字体回退，不影响 SWF 内嵌文字、游戏舞台和触控映射。可以从启动器更改，重新进入游戏生效。

## 延续修复
保留 Build121 的每日签到路径兼容、紧凑工具菜单、本地代理重入清理和 .sgpatch 导入等功能。

## 版本
1.05 Build122，Bundle ID `cn.shiguanghao.launcher`，可通过兼容签名方式覆盖安装。此次日志使用的是 `2026110401` 资源包（0.18.0），但该新资源尚未进行完整文件差异验证。

## 验证限制
GitHub Actions 构建通过不等于真机游戏基地和所有字体面板均通过；需用户在游戏服务器上实际进入基地并提供诊断日志，才能确认完全解决。
