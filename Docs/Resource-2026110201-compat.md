# 2026-11-02 资源参考包与正式版 1.03 适配

来源：用户上传的 `Shiguang-App-Update-Resources-2026110201.zip`；README 明确写明，这是来自 `拾光号-美化整合包-2026110201.srom` 的**部分核心文件**，并非完整 .srom 或 IPA，未包含场景/精灵/音效。文件 SHA-256 按所提供 `manifest.json` 与本地 ZIP 实测校验一致。此报告不代表在所有 iPhone 上已经真机测试通过。

## 实际包内容与关键版本信息
- ZIP 共 18 项（16 个 `NieoData/` 文件 + `manifest.json`、`README.txt`），解压后约 9.56 MB。
- 核心入口：`NieoData/Client.swf` 82,806 字节；`NieoData/dll/NieoCore.swf` 3,062,536 字节；`NieoData/login/Login.swf` 5,114,985 字节；`NieoData/dll/Assets.swf` 882,146 字节。
- 以上四个 SWF 文件头均为 `CWS`（压缩 SWF）；不是 `FWS`。不能按纯未压缩 SWF 解码。
- `NieoData/config/dll.xml` 声明 `<item name="核心资源" path="dll/NieoCore.swf?2026110201" ver="2026110201"/>`。
- `NieoData/config/ServerR.xml` 使用 `127.0.0.1:32973` 的登录代理和相对地址 `resource/`，与当前微端网络代理和本地资源服务架构匹配。
- `NieoData/version.swf` 20,512 字节，是私服 PVM 格式的版本数据，**不是标准 SWF**，因此保留现有 `pvm-compat.js` 和 URLStream 兼容逻辑。
- 提供 `assets/index.js`、`assets/nieo_wasm_core_bg.wasm`、`index.html`，原网页前端依赖 React/模块加载；正式版继续使用 Ruffle 直接加载 Client.swf，不重新切换到原始 React 网页，以避免引入登录兼容回归。

## 核心文件 SHA-256 参考
```
Client.swf          D64A9E3AF813324F6E1F9844E74EEE16DEE5D76A4C8A26C417585467A3C3E59F
dll/NieoCore.swf    AFBC6FC236D8539BA5336BF0762702CC32315DC9B74CA66FAB9C203EC54164AC
login/Login.swf     830749FF66778893BB038D85B9334874F78849895AF91A5D73059111984ED258
dll/Assets.swf      273BF57545E608A1C60C4299D01A138E61585A9FAD4CF9DFAD773B92A5C1BECA
version.swf         E3601421EFF406A367BA9237F84154BA1D8A5CC2CD09365A5170C332CDBE1E7D
config/dll.xml      EFAEDDD785B687832B5764DC6C744F10620AAC2A8AF8F1BCD0A1029D2FC9C944
```

## 正式版 1.03 的适配与安全界限
1. 启动器识别 `config/dll.xml` 的核心版本数字，在首页报告识别结果；其他版本不武断视为已适配。
2. 检查 NieoData 游戏资源中的 `resource/main_resource.swf`、`resource/ui.swf` 和 `resource/map/1.swf`，避免把只含 16 个核心文件的参考 ZIP 当成完整游戏。导入参考-only ZIP 会在解压前提醒用户使用完整 .srom。
3. 兼容省资源模式默认关闭。打开时只降低 Ruffle 的抗锯齿质量并短时缓存 `<=32 KiB` 的静态服装/道具图标；地图、核心 DLL、PVM、登录和大量资源仍 `no-store`。不强制改 GPU 后端、DPR、SWF 原始帧率或点击坐标。
4. 保留现有登录 socketProxy、PVM + ByteLoader 双层兼容、键盘、NoNo 鼠标辅助、直接触屏延迟和完整 .srom 的 CRC32 导入校验。
5. 游戏页面异常时允许直接导出诊断日志，避免必须先退回启动器。
6. **不要把参考 ZIP 内的 16 项合并覆盖用户私有的完整游戏目录；不要把它当成完整游戏包直接内置 IPA。**

## 需要真机验证
安装完整 `拾光号-美化整合包-2026110201.srom`，验证选服、进入地图、NoNo、中文键盘、精灵背包和战斗；兼容模式开/关分别测试重复打开背包和图标是否更新。对 WebKit 内容进程终止的根本原因尚无 Jetsam/IPS 证据，不能承诺 1.03 根治特定 iPhone 15 Pro 的崩溃。
