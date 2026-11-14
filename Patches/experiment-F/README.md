# F 版 Rust 内核资源生命周期诊断（2026-11-14）

实验基线：
- 正式 1.09 Build 136 的 UI、Swift、资源代理保持不变；原正式版分支无更改。
- 测试版 D：DPR 1.5，WebGL (automatic)，战斗 HTTP 缓存开启，WASM 线性内存与 WebGL 对象计数探针保留。
- F 版唯一新增的 Rust 数据：每 150 帧采样 MovieLibraries 中的资源库数量、其角色定义总数以及 LoadManager 当前活跃加载器数。
- Rust 源码固定在 Ruffle nightly-2026-11-13 commit 65d984777f5acc28e18fe6c3e89d28266fc1fb75；不会跟随 master 漂移。
- Ruffle 官方 Web 需要 wasm-bindgen CLI 0.2.127。使用 GitHub Actions Ubuntu 编译自托管 Web Ruffle JS+WASM，再把其产物合入独立的未签名测试版 IPA。

这些计数不是 AVM2 GC 存活对象数，也不能直接等于内存泄漏。
- known_movies：Ruffle 持有的已登记影片定义，内存占用受每个影片的实际大小影响。
- characters：每个影片定义库里的角色定义项总数，包括图片、字体、形状等内容，不代表当前正在显示。
- active_loaders：仍处于 LoadManager 中的加载器，不包括已完成并移除的加载请求。
- WASM memory：是线性内存已分配容量，而不是实时存活对象大小。
- WebGL 对象净创建量只是 JS API 观察值，不等于实际 GPU 显存或泄漏确认。

F 版不能通过 JavaScript 直接获知 Rust 真实分配器的空闲块，必须谨慎区分“已增长”和“未回收”。
为了避免不能复现的修复，F 版不强制运行 GC、不执行 MovieClip.unload、不清理资源库。
