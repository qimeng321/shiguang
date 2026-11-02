# 拾光号 iOS 测试版 1.1 · 手机资源补丁格式（第一版）

本功能是**一个补丁导入接口**，不附带任何未经确认的补丁 SWF。开发者收到实际手机版适配资源后，按本规范生成补丁 ZIP。**测试版 1.1 不改变正式版 1.03 的仓库分支、IPA、沙盒、资源和配置。**

## 安装隔离与适用范围

- iOS Bundle ID：`cn.shiguanghao.launcher.beta`，与正式版 `cn.shiguanghao.launcher` **并排安装，沙盒互不相通**。
- 首次运行测试版必须单独导入一次完整 `.srom`；测试版不能访问正式版已安装的 2–3 GB 游戏资源，这是 iOS 应用隔离决定的。
- 测试版启动器首页 →「手机适配补丁」→「导入补丁」，通过 Files 选择 `.sgpatch` 或 `.zip`。无需重新导入原 `.srom` 才能切换新补丁。
- 安装后**退出并重新进入游戏**才能应用。首页「撤销补丁」则移除覆盖层，游戏重新进入后原貌恢复。
- 只允许覆盖 `NieoData/resource/` 下的资源，包括 `.swf`, `.png`, `.jpg`, `.jpeg`, `.webp`, `.gif`, `.xml`, `.json`, `.mp3`。
- 不允许修改游戏入口 `Client.swf`、`dll/`、`config/`、`login/`、PVM `version.swf`、Ruffle、Javascript 或 App 的原生程序。**可用于对 NoNo、背包、地图 UI 等资源级适配，不能任意插入原生功能或自动改变所有触屏行为。**
- 一个时刻只激活一份补丁。替换旧补丁前检查 ZIP 清单、文件路径、目标核心版本和 CRC32；通过后替换覆盖目录。导入失败不会覆盖原游戏资源，也尽量保留之前的补丁。
- 游戏资源服务只对 `resource/` 路径查看覆盖层；覆盖文件存在则返回补丁资源，其他请求直接走原游戏文件（包括全部非 `resource/` 请求）。
- ZIP 单包解压后不超过 **512 MiB**，最多 **2048 个实际游戏文件**。路径禁止 `..`、绝对路径、反斜杠、符号链接、不支持扩展名、百分号等；列出的路径必须与 ZIP 中的文件**完全一致**。
- SWF 可能包含可执行 Flash 逻辑，**仅安装可信开发者制作的补丁**，不能把任意来历的 ZIP 当作适配补丁。

## 文件布局

ZIP 根目录必须直接包含：

```
mobile-patch.json
resource/
  nono/
    super/
      nono_5.swf
  module/
    bag/
      bagUI.swf
```

这里的 `.swf` 仅是**示例文件名和路径**，应使用实际已修改的游戏 SWF，不能放空文件或占位内容。如果只改 NoNo，`files` 中就只列 NoNo 项；不需要附带未改动的游戏资源。

`mobile-patch.json`（UTF-8，最多 32 KiB）示例：

```json
{
  "format": "shiguang-mobile-patch-v1",
  "name": "拾光号手机适配补丁",
  "version": "0.1.0",
  "targetRevision": "2026110201",
  "files": [
    "resource/nono/super/nono_5.swf",
    "resource/module/bag/bagUI.swf"
  ]
}
```

`targetRevision` 可省略；如果填写，只有当前完整美化包的核心 `config/dll.xml` 版本相同时才允许安装或启用。为防资源版本混用，推荐始终填写。文件清单里的大小写必须与实际 ZIP 文件完全相符。

## 从电脑制作补丁包

1. 用工具对需要手机版适配的少数 SWF 或图像资源完成改动；保持资源的原始相对路径。
2. 在文件夹根目录编写 `mobile-patch.json`。
3. **把 `mobile-patch.json` 和 `resource/` 直接压成 ZIP**；不要把外层父文件夹一起压进去。可将成品扩展名从 `.zip` 改为 `.sgpatch`。
4. 导入测试版 1.1，查看状态提示，然后重新进入游戏验证。若有黑屏、NoNo、背包或触控问题，可以从首页导出 `diagnostics.txt`。

**目前 1.1 实装的是补丁导入、校验、覆盖、撤销接口，尚无用户实际提供的适配 SWF 可进行资源级真机效果验证。**
