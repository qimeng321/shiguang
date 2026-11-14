# 拾光号原生 Ruffle 游戏内核测试版 B001

本分支为真正使用原生 Rust + Metal Ruffle 的 iOS 独立测试 App。不会覆盖网页版正式版 1.08 Build130。

上游：https://github.com/madsmtm/ruffle-ios ，固定提交 c3489324265221ff5089442797be671df14fdcdb。

## 测试方法

1. 签名独立 IPA 并安装「拾光号原生测试」，Bundle ID 为 cn.shiguanghao.nativegame.test。
2. 打开 App，点击右上角 + ，从文件 App 选择完整拾光号美化整合包 .srom / .zip，不是 .sgpatch。
3. iOS 文件选择器先将资源包复制到测试 App 沙盒，再在后台解压；导航标题显示进度，保持前台运行，建议可用空间不少于 10GB。
4. 解压后自动使用原生 Ruffle 加载 Client.swf，资源从 http://127.0.0.1:18765/ 动态提供，无需 WebKit。
5. 下次启动若资源仍在将自动进入游戏；可通过顶部返回按钮回到文件库。
6. 依次观察 Client.swf、登录、选服、主场景、背包和命运之轮的实际效果，记录首次失败阶段。

## 限制

- 使用真原生 Ruffle 和本地 ZIP 解压资源服务；与正式版 1.08 的资源目录和证书标识完全隔离。
- 解压安全限制为 120000 个文件 / 16GiB，拒绝危险路径或符号链接。
- 资源服务支持本地 GET、HEAD、Range，补充缺失的 ip.txt 登录地址 202.189.22.79:22973。
- 暂未移植正式版的 WebSocket/TCP 桥接、PVM/ByteLoader 事件兼容、手机 sgpatch、增量更新、键盘与精准鼠标的完整逻辑；测试版可能卡在登录或加载阶段，需要真机日志继续定位。
- 此版是第一步「直接启动 Client.swf」可行性验证，不宣称可以完整游玩、解决闪退或命运之轮异常。

## 构建

工作流 .github/workflows/ios-native-ruffle-game.yml 自动克隆上游、打入 NativeRuffle/patch-upstream.py，编译 Rust iOS ARM64 并打包独立未签名 IPA 和源码。原正式版分支不变。
