import Foundation
import Network

final class GameServer {
    private let root: URL
    private let ruffle: URL
    private let queue = DispatchQueue(label: "cn.shiguanghao.launcher.http")
    // Use browser-safe local ports; retry if a port is occupied.
    private static let httpPortCandidates: [UInt16] = [18765, 18766, 18767, 18768, 18769]
    private var listener: NWListener?
    private var readyHTTPPort: UInt16?
    private var failureMessage: String?
    var startError: String? { queue.sync { failureMessage } }
    var bridgeError: String? { bridge?.failureDescription }
    private let packagedWebApp: Bool
    private var tracedRequestCount = 0
    private let maxTracedRequests = 300
    private var versionGetCount = 0
    private var proceededBeyondVersion = false
    private var inspectedVersionHeader = false

    // Diagnose the PVM header directly in the saved file; never modify it.
    private func inspectPVMHeader(_ file: URL) {
        guard !inspectedVersionHeader else { return }
        inspectedVersionHeader = true
        guard let handle = try? FileHandle(forReadingFrom: file),
              let sample = try? handle.read(upToCount: 256),
              sample.count >= 6 else {
            LaunchDiagnostics.log("[PVM 静态检查] version.swf 不可读或不足 6 字节")
            return
        }
        try? handle.close()
        let bytes = [UInt8](sample)
        let size = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.intValue ?? 0
        let stamp = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        let count = Int(UInt16(bytes[4]) << 8 | UInt16(bytes[5]))
        let headerSize = 6 + count * 24
        let preview = bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        let validHeader = headerSize <= size && count <= 2048
        let zlibLikely = sample.count > headerSize + 1 && bytes[headerSize] == 0x78 && ((Int(bytes[headerSize]) << 8 | Int(bytes[headerSize + 1])) % 31 == 0)
        LaunchDiagnostics.log("[PVM 静态检查] version.swf 总字节=\(size)；前8字节=\(preview)；修订号=\(stamp)；表项=\(count)；头部应占=\(headerSize)；结构=\(validHeader ? "头部长度合理" : "头部长度异常")；数据区Zlib=\(zlibLikely ? "疑似有效" : "未识别")；表项0可合法")
        if validHeader {
            let fileNameBytes = Array(bytes.dropFirst(6).prefix(20))
            let fileName = String(decoding: fileNameBytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            let safeName = fileName.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "._-/".contains($0)) }
            LaunchDiagnostics.log("[PVM 静态检查] 首项名称（过滤后）：\(safeName.prefix(24))")
        }
    }

    // Most HTTP requests were deliberately not logged in v2.0. Trace game boot
    // resources explicitly to distinguish 'Flash never requested it' from 404.
    private func traceRequest(_ method: String, _ path: String, status: Int, size: UInt64? = nil) {
        let lower = path.lowercased()
        if method == "GET" && status == 200 {
            if lower == "/version.swf" {
                versionGetCount += 1
                LaunchDiagnostics.log("PVM 版本初始化：实际请求 version.swf，第 \(versionGetCount) 次")
                if versionGetCount == 3 { LaunchDiagnostics.log("[PVM 进度] 第三次 version.swf 请求已出现，说明头部回调成功推进到主体读取") }
                if versionGetCount == 2 {
                    queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                        guard let self, !self.proceededBeyondVersion, self.versionGetCount == 2 else { return }
                        LaunchDiagnostics.log("[阶段诊断] 第二次 version.swf 后 5 秒未见第三次主体 GET，也无登录或 DLL GET，请在游戏界面停留至少 20 秒。")
                    }
                    queue.asyncAfter(deadline: .now() + 15) { [weak self] in
                        guard let self, !self.proceededBeyondVersion else { return }
                        LaunchDiagnostics.log("[阶段诊断] version.swf 请求后 15 秒内未观察到 DLL 或登录资源 GET")
                    }
                }
            } else if lower.hasPrefix("/dll/") || lower == "/config/dll.xml" || lower.hasPrefix("/login/") {
                proceededBeyondVersion = true
                LaunchDiagnostics.log("[阶段诊断] 已开始加载：\(path)")
            }
        }
        guard lower.hasPrefix("/config/") || lower.hasPrefix("/resource/") ||
              lower.hasPrefix("/login/") || lower.hasPrefix("/dll/") ||
              lower.hasSuffix(".swf") || lower.hasSuffix(".xml") ||
              lower == "/assets/nieo_wasm_core_bg.wasm" else { return }
        guard tracedRequestCount < maxTracedRequests else {
            if tracedRequestCount == maxTracedRequests {
                LaunchDiagnostics.log("HTTP 详细记录达到 300 条，后续请求已省略")
            }
            tracedRequestCount += 1
            return
        }
        tracedRequestCount += 1
        let sizeInfo = size.map { "; 字节=\($0)" } ?? ""
        LaunchDiagnostics.log("HTTP 资源请求：\(method) \(path) → \(status)\(sizeInfo)")
    }
    private let bridge: GameSocketBridge?

    init(root: URL, packagedWebApp: Bool = false) throws {
        self.root = root.resolvingSymlinksInPath()
        self.packagedWebApp = packagedWebApp
        self.bridge = packagedWebApp ? try GameSocketBridge() : nil
        guard let assets = Bundle.main.url(forResource: "Ruffle", withExtension: nil),
              FileManager.default.fileExists(atPath: assets.appendingPathComponent("ruffle.js").path) else {
            throw ServerError.missingRuffle
        }
        self.ruffle = assets.resolvingSymlinksInPath()
        let engineInfo = assets.appendingPathComponent("engine-version.txt")
        if let text = try? String(contentsOf: engineInfo, encoding: .utf8) {
            LaunchDiagnostics.log("[引擎版本] " + text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            LaunchDiagnostics.log("[引擎版本] 内置旧版 Ruffle（此包未附带 engine-version.txt）")
        }
        try startHTTPListener(at: 0)
    }

    deinit { listener?.cancel() }

    /// Bind one of our known WebKit-safe ports on loopback only.
    /// NWListener.port must not be trusted before its .ready callback.
    private func startHTTPListener(at index: Int) throws {
        let portNumber = Self.httpPortCandidates[index]
        guard let localPort = NWEndpoint.Port(rawValue: portNumber) else {
            throw ServerError.invalidLocalPort
        }
        let parameters = NWParameters.tcp
        // Do not simultaneously specify requiredLocalEndpoint (including a port)
        // and the listener's `on:` port: Network.framework can reject this
        // conflicting setup with NWError.posix(.EINVAL), errno 22.
        // Limit this local HTTP service to the loopback interface.
        parameters.requiredInterfaceType = .loopback
        let newListener = try NWListener(using: parameters, on: localPort)
        listener = newListener
        failureMessage = nil
        readyHTTPPort = nil
        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                LaunchDiagnostics.log("本地 HTTP 监听成功，端口：\(portNumber)")
                // Only expose a URL once the socket is actually accepting traffic.
                self.readyHTTPPort = portNumber
                self.failureMessage = nil
            case .failed(let error):
                LaunchDiagnostics.log("本地 HTTP 端口 \(portNumber) 监听失败：\(error.localizedDescription)")
                self.readyHTTPPort = nil
                newListener.cancel()
                let next = index + 1
                if next < Self.httpPortCandidates.count {
                    do { try self.startHTTPListener(at: next) }
                    catch { self.failureMessage = "无法启动本地 HTTP 服务：\(error.localizedDescription)" }
                } else {
                    self.failureMessage = "本地端口均不可用（18765–18769）：\(error.localizedDescription)"
                }
            default:
                break
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        newListener.start(queue: queue)
    }

    func playURL(for entry: String) -> URL? {
        if let bridge, !bridge.isReady { return nil }
        guard let port = queue.sync(execute: { readyHTTPPort }), port > 0 else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = packagedWebApp ? "/__micro/game.html" : "/index.html"
        if !packagedWebApp { components.queryItems = [URLQueryItem(name: "entry", value: entry)] }
        return components.url
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self, error == nil, let data,
                  let request = String(data: data, encoding: .utf8),
                  request.contains("\r\n") else {
                connection.cancel()
                return
            }
            self.respond(to: request, connection: connection)
        }
    }

    private func respond(to request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        let line = lines.first ?? ""
        let rangeHeader = lines.first(where: { $0.lowercased().hasPrefix("range:") })
            .map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD",
              let components = URLComponents(string: "http://127.0.0.1\(parts[1])") else {
            sendText("Bad Request", status: 400, connection: connection)
            return
        }
        let headOnly = parts[0] == "HEAD"
        let path = components.path
        let lower = path.lowercased()
        if lower == "/version.swf" && !headOnly {
            let raw = components.query ?? ""
            let queryKind = (UInt64(raw) ?? 0) > 100_000_000 ? "修订号请求" : (raw.isEmpty ? "无查询参数" : "随机防缓存请求")
            LaunchDiagnostics.log("[PVM 请求阶段] GET version.swf：\(queryKind)（不记录实际查询值）")
        }
        if lower == "/" || lower == "/index.html" ||
           lower.hasSuffix("/index.js") || lower.hasSuffix("/ruffle.js") ||
           lower.hasSuffix("/client.swf") || lower.hasSuffix("/nieo_wasm_core_bg.wasm") ||
           lower.hasSuffix("/video.mp4") {
            LaunchDiagnostics.log("HTTP 请求：\(parts[0]) \(path)")
        }
        // The original .srom web app creates a Flash <object> in React.
        // WKWebView cannot render Flash without a polyfill. Serve our bundled
        // Ruffle files even when the package contains its own index.html.
        if path.hasPrefix("/ruffle/") {
            serve(relative: String(path.dropFirst(8)), below: ruffle, headOnly: headOnly, rangeHeader: rangeHeader, connection: connection)
            return
        }
        if packagedWebApp && path == "/__micro/status" {
            let entered = bridge?.hasEnteredGame ?? false
            let body = entered ? "{\"enteredGame\":true}" : "{\"enteredGame\":false}"
            send(data: Data(body.utf8), mime: "application/json",
                 headOnly: headOnly, connection: connection)
            return
        }
        if packagedWebApp && path == "/__micro/game.html" {
            versionGetCount = 0
            proceededBeyondVersion = false
            inspectedVersionHeader = false
            if let bridge {
                queue.asyncAfter(deadline: .now() + 22) {
                    if !bridge.hasReceivedClient {
                        LaunchDiagnostics.log("[登录网络诊断] 启动后22秒未出现 Flash→WebSocket 本地连接；请核对游戏实际 Socket 目标与 Ruffle 代理映射")
                    }
                }
            }
            let html = page(swfURL: "/Client.swf", baseURL: "/")
            LaunchDiagnostics.log("[启动模式] 直接启动 Client.swf；PVM 计数已按本次启动重置")
            send(data: Data(html.utf8), mime: "text/html; charset=utf-8",
                 headOnly: headOnly, connection: connection)
            return
        }
        if packagedWebApp {
            let relative = path == "/" ? "index.html" : String(path.dropFirst())
            if relative == "index.html" {
                servePackagedIndex(headOnly: headOnly, connection: connection)
            } else if relative.lowercased() == "ip.txt" {
                // The Flash login client fetches /ip.txt AFTER the player submits
                // credentials. Without it, it never reaches Flash Socket.connect.
                // Prefer the package's own file when available; only synthesize
                // a fallback from the known Windows microclient configuration.
                if let original = safeFile(relative, below: root),
                   FileManager.default.fileExists(atPath: original.path) {
                    LaunchDiagnostics.log("[登录地址] 使用美化包自带 ip.txt（保持原文件内容）")
                    serve(relative: relative, below: root, headOnly: headOnly,
                          rangeHeader: rangeHeader, connection: connection)
                } else {
                    let endpoint = GameSocketBridge.serverHost + ":" + String(GameSocketBridge.serverPort)
                    LaunchDiagnostics.log("[登录地址] 美化包没有 ip.txt；依据 Windows 微端线上配置返回 "
                                          + endpoint + "（HTTP 200，纯文本）")
                    send(data: Data(endpoint.utf8),
                         mime: "text/plain; charset=utf-8",
                         headOnly: headOnly, connection: connection)
                    if !headOnly, let bridge {
                        queue.asyncAfter(deadline: .now() + 12) {
                            if !bridge.hasReceivedClient {
                                LaunchDiagnostics.log("[登录网络诊断] ip.txt 已返回，12秒内仍无 Flash Socket 连接；需继续核查登录 SWF 对返回内容的解析及 Ruffle Socket 支持")
                            }
                        }
                    }
                }
            } else {
                serve(relative: relative, below: root, headOnly: headOnly, rangeHeader: rangeHeader, connection: connection)
            }
            return
        }
        if path == "/index.html" || path == "/" {
            let entry = components.queryItems?.first(where: { $0.name == "entry" })?.value ?? ""
            guard let file = safeFile(entry, below: root),
                  file.pathExtension.lowercased() == "swf" else {
                LaunchDiagnostics.log("HTTP 400：无效游戏入口：\(entry)；资源根目录：\(root.path)")
                let detail = "游戏资源入口不存在或无法读取。\n入口：\(entry)\n资源根目录：\(root.path)\n请返回首页查看资源检查并提供 diagnostics.txt。"
                sendErrorPage(detail, status: 400, headOnly: headOnly, connection: connection)
                return
            }
            LaunchDiagnostics.log("HTTP 200：已验证 SWF 入口：\(file.path)")
            let urlPath = "/game/" + entry.split(separator: "/").map {
                String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            }.joined(separator: "/")
            let basePath = (urlPath as NSString).deletingLastPathComponent + "/"
            let html = page(swfURL: urlPath, baseURL: basePath)
            LaunchDiagnostics.log("HTTP 200：生成 SWF 后备网页，SWF=\(urlPath)，HTML 字节=\(html.utf8.count)")
            send(data: Data(html.utf8), mime: "text/html; charset=utf-8", headOnly: headOnly, connection: connection)
            return
        }
        if path.hasPrefix("/game/") {
            serve(relative: String(path.dropFirst(6)), below: root, headOnly: headOnly, rangeHeader: rangeHeader, connection: connection)
            return
        }
        sendText("Not Found", status: 404, connection: connection)
    }

    /// Add Ruffle to the supplied HTML without changing files in the imported .srom.
    /// The original page is responsible for loading /assets/index.js and its own
    /// WASM networking bridge. The JS dynamically creates <object data="Client.swf">.
    private func servePackagedIndex(headOnly: Bool, connection: NWConnection) {
        guard let file = safeFile("index.html", below: root),
              let html = try? String(contentsOf: file, encoding: .utf8) else {
            LaunchDiagnostics.log("HTTP 404：网页入口 index.html 缺失")
            sendText("Missing index.html", status: 404, connection: connection)
            return
        }
        // Never load two copies when a different package includes Ruffle itself.
        if html.contains("ruffle.js") {
            send(data: Data(html.utf8), mime: "text/html; charset=utf-8",
                 headOnly: headOnly, connection: connection)
            return
        }
        // Only this known host/port is mapped. No system-wide proxy or arbitrary relay.
        let bootstrap = #"""
        <style id="shiguang-centered-game">
          /* The React client creates a 960x560 Flash object. Never pin it to
             top-left: center the Ruffle host in the iPad viewport instead.
             Its original 12:7 aspect ratio is preserved without cropping. */
          html, body {
            width: 100% !important; height: 100% !important;
            margin: 0 !important; padding: 0 !important;
            overflow: hidden !important; background: #000 !important;
          }
          #root {
            position: fixed !important; inset: 0 !important;
            display: flex !important; align-items: center !important;
            justify-content: center !important;
            margin: 0 !important; padding: 0 !important;
            width: 100vw !important; height: 100vh !important;
            height: 100dvh !important; background: #000 !important;
          }
          #root > div {
            width: 100% !important; height: 100% !important;
            display: flex !important; align-items: center !important;
            justify-content: center !important;
            margin: 0 !important; padding: 0 !important;
            overflow: hidden !important;
            background: #000 !important;
          }
          /* Strong centering fallback for Ruffle's replacement custom element,
             even if its own wrapper doesn't participate in React's flexbox. */
          object[data$=".swf"], embed[src$=".swf"],
          ruffle-object, ruffle-player, ruffle-embed {
            position: fixed !important;
            left: 50vw !important; top: 50vh !important;
            top: 50dvh !important;
            right: auto !important; bottom: auto !important;
            transform: translate(-50%, -50%) !important;
            transform-origin: center center !important;
            width: min(100vw, 171.4286dvh) !important;
            height: min(100dvh, 58.3333vw) !important;
            max-width: 100vw !important; max-height: 100dvh !important;
            margin: 0 !important; padding: 0 !important;
            border: 0 !important; box-shadow: none !important;
            box-sizing: border-box !important;
            display: block !important;
          }
        </style>
        <script>
          window.RufflePlayer = window.RufflePlayer || {};
          window.RufflePlayer.config = Object.assign({}, window.RufflePlayer.config || {}, {
            publicPath: "/ruffle/",
            polyfills: true,
            autoplay: "on",
            unmuteOverlay: "hidden",
            splashScreen: false,
            letterbox: "on",
            scale: "showAll",
            forceScale: true,
            salign: "",
            forceAlign: true,
            allowScriptAccess: true,
            logLevel: "debug",
            socketProxy: [{
              host: "103.91.210.16",
              port: 22973,
              proxyUrl: "ws://127.0.0.1:32973"
            }]
          });
        </script>
        <script src="/ruffle/ruffle.js"></script>
        <script>
          // The original React client draws a z-index:1000 full-screen
          // /video.mp4 splash overlay that stays black if playback fails.
          // Auto-dismiss it through the original React onClick handler.
          (function () {
            var finished = false;
            var observer;
            function skipOriginalSplash() {
              if (finished) return;
              var video = document.querySelector('video[src="/video.mp4"],video[src$="/video.mp4"]');
              if (!video || !video.parentElement) return;
              finished = true;
              if (observer) observer.disconnect();
              video.parentElement.click();
              console.log('[Shiguang] 已跳过原始视频启动遮罩');
            }
            observer = new MutationObserver(skipOriginalSplash);
            observer.observe(document.documentElement, { childList: true, subtree: true });
            document.addEventListener('DOMContentLoaded', skipOriginalSplash);
            setTimeout(skipOriginalSplash, 600);
            setTimeout(function () { if (observer) observer.disconnect(); }, 10000);
          })();
        </script>
        """#
        LaunchDiagnostics.log("HTML 已注入 Ruffle 无遮罩配置；游戏 12:7 保持比例并在视口中央显示")
        let updated: String
        if let headEnd = html.range(of: "</head>", options: [.caseInsensitive]) {
            updated = html.replacingCharacters(in: headEnd, with: bootstrap + "\n</head>")
        } else {
            updated = bootstrap + "\n" + html
        }
        send(data: Data(updated.utf8), mime: "text/html; charset=utf-8",
             headOnly: headOnly, connection: connection)
    }

    private func safeFile(_ relative: String, below base: URL) -> URL? {
        let decoded = relative.removingPercentEncoding ?? relative
        let parts = decoded.split(separator: "/", omittingEmptySubsequences: false)
        guard !decoded.hasPrefix("/"), !decoded.contains("\\"),
              !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { return nil }
        let resolved = base.appendingPathComponent(decoded).resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(base.path + "/"),
              (try? resolved.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        return resolved
    }

    /// Serve files with a real byte-range implementation. iOS media playback
    /// requires 206 responses for HTTP Range requests (including video.mp4).
    private func serve(relative: String, below base: URL, headOnly: Bool,
                       rangeHeader: String?, connection: NWConnection) {
        guard let file = safeFile(relative, below: base),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: file) else {
            traceRequest(headOnly ? "HEAD" : "GET", "/" + relative, status: 404)
            LaunchDiagnostics.missingResource(relative)
            sendText("Not Found: \(relative)", status: 404, connection: connection)
            return
        }
        if relative.lowercased() == "version.swf" && !headOnly {
            inspectPVMHeader(file)
            LaunchDiagnostics.log("[PVM 传输] GET version.swf 已收到（查询参数已省略）")
        }
        let total = size.uint64Value
        var first: UInt64 = 0
        var last: UInt64 = total == 0 ? 0 : total - 1
        var isPartial = false
        if let header = rangeHeader {
            // Only a single byte-range request is supported, as used by iOS
            // when retrieving portions of an MP4 file.
            let h = header.trimmingCharacters(in: .whitespaces)
            guard h.lowercased().hasPrefix("bytes=") else {
                try? handle.close()
                sendRangeUnsatisfiable(total: total, connection: connection)
                return
            }
            let spec = String(h.dropFirst(6))
            let pieces = spec.split(separator: "-", omittingEmptySubsequences: false)
            guard pieces.count == 2, !spec.contains(","), total > 0 else {
                try? handle.close()
                sendRangeUnsatisfiable(total: total, connection: connection)
                return
            }
            if pieces[0].isEmpty {
                // Suffix ranges: bytes=-500 means the last 500 bytes.
                guard let suffix = UInt64(pieces[1]), suffix > 0 else {
                    try? handle.close()
                    sendRangeUnsatisfiable(total: total, connection: connection)
                    return
                }
                first = total - min(suffix, total)
            } else {
                guard let start = UInt64(pieces[0]), start < total else {
                    try? handle.close()
                    sendRangeUnsatisfiable(total: total, connection: connection)
                    return
                }
                first = start
                if !pieces[1].isEmpty {
                    guard let stop = UInt64(pieces[1]), stop >= first else {
                        try? handle.close()
                        sendRangeUnsatisfiable(total: total, connection: connection)
                        return
                    }
                    last = min(stop, total - 1)
                }
            }
            isPartial = true
        }
        let byteCount = total == 0 ? UInt64(0) : last - first + 1
        let response = isPartial ? "206 Partial Content" : "200 OK"
        traceRequest(headOnly ? "HEAD" : "GET", "/" + relative,
                     status: isPartial ? 206 : 200, size: byteCount)
        let contentRange = isPartial ? "Content-Range: bytes \(first)-\(last)/\(total)\r\n" : ""
        let header = "HTTP/1.1 \(response)\r\nContent-Type: \(mime(for: file))\r\nContent-Length: \(byteCount)\r\nAccept-Ranges: bytes\r\n\(contentRange)Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        if !headOnly {
            do { try handle.seek(toOffset: first) }
            catch {
                try? handle.close()
                sendText("File seeking error", status: 400, connection: connection)
                return
            }
        }
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { connection.cancel(); return }
            if let error {
                LaunchDiagnostics.log("[HTTP] 响应头发送失败：" + error.localizedDescription)
                try? handle.close()
                connection.cancel()
            } else if headOnly || byteCount == 0 {
                try? handle.close()
                self.finishHTTPResponse(connection)
            } else {
                let pvm = relative.lowercased() == "version.swf" && !isPartial
                self.stream(handle, to: connection, remaining: byteCount, observeCompletion: pvm)
            }
        })
    }

    // Send TCP FIN after the last response byte, rather than immediately aborting
    // the connection. Flash URLStream depends on complete/progress events.
    private func finishHTTPResponse(_ connection: NWConnection, pvm: Bool = false) {
        connection.send(content: nil, contentContext: .finalMessage,
                        isComplete: true, completion: .contentProcessed { error in
            if pvm {
                LaunchDiagnostics.log(error == nil
                    ? "[PVM 传输] 已发送 TCP FIN；等待 Flash URLStream 收到正常结束"
                    : "[PVM 传输] TCP FIN 失败：" + (error?.localizedDescription ?? "未知"))
            }
            self.queue.asyncAfter(deadline: .now() + .seconds(2)) {
                connection.cancel()
            }
        })
    }

    private func sendRangeUnsatisfiable(total: UInt64, connection: NWConnection) {
        let header = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(total)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            if error == nil { self?.finishHTTPResponse(connection) }
            else { connection.cancel() }
        })
    }

    private func stream(_ handle: FileHandle, to connection: NWConnection,
                        remaining: UInt64, observeCompletion: Bool = false) {
        guard remaining > 0 else {
            try? handle.close()
            if observeCompletion { LaunchDiagnostics.log("[PVM 传输] version.swf 数据已发完，准备 TCP FIN") }
            finishHTTPResponse(connection, pvm: observeCompletion)
            return
        }
        let count = Int(min(remaining, 64 * 1024))
        guard let chunk = try? handle.read(upToCount: count), !chunk.isEmpty else {
            try? handle.close()
            if observeCompletion { LaunchDiagnostics.log("[PVM 传输] 读取异常，剩余 \(remaining) 字节") }
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { try? handle.close(); connection.cancel(); return }
            if error == nil {
                self.stream(handle, to: connection, remaining: remaining - UInt64(chunk.count),
                            observeCompletion: observeCompletion)
            } else {
                if observeCompletion { LaunchDiagnostics.log("[PVM 传输] 写入失败：" + (error?.localizedDescription ?? "未知")) }
                try? handle.close()
                connection.cancel()
            }
        })
    }

    private func sendErrorPage(_ detail: String, status: Int, headOnly: Bool, connection: NWConnection) {
        let escaped = detail
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="background:#111;color:#fff;font:16px/1.7 -apple-system,sans-serif;padding:72px 24px;white-space:pre-wrap">
        <h2>拾光号：游戏启动失败（HTTP \(status)）</h2><p>\(escaped)</p></body></html>
        """
        send(data: Data(html.utf8), mime: "text/html; charset=utf-8", status: status,
             headOnly: headOnly, connection: connection)
    }

    private func sendText(_ text: String, status: Int, connection: NWConnection) {
        send(data: Data(text.utf8), mime: "text/plain; charset=utf-8", status: status, headOnly: false, connection: connection)
    }

    private func send(data: Data, mime: String, status: Int = 200, headOnly: Bool, connection: NWConnection) {
        let reason = status == 200 ? "OK" : status == 400 ? "Bad Request" : "Not Found"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(mime)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + (headOnly ? Data() : data), completion: .contentProcessed { [weak self] error in
            if error == nil { self?.finishHTTPResponse(connection) }
            else { connection.cancel() }
        })
    }

    private func mime(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "wasm": return "application/wasm"
        case "swf": return "application/x-shockwave-flash"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        case "ttf": return "font/ttf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }

    // Native microclient style SWF entry: no original React SPA or network WASM.
    private func page(swfURL: String, baseURL: String) -> String {
        func json(_ value: String) -> String {
            let data = try! JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed])
            return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
        }
        return """
        <!doctype html><html lang="zh-CN"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover,user-scalable=no">
        <style>
          :root {--game-w:960px;--game-h:560px}
          html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}
          #game{position:fixed;inset:0;display:flex;justify-content:center;align-items:center}
          ruffle-player{display:block;flex:none;width:var(--game-w)!important;height:var(--game-h)!important}
          #message{position:fixed;inset:0;display:flex;justify-content:center;align-items:center;
                   background:#000;color:#b9c1d0;font:14px -apple-system,sans-serif;pointer-events:none}
          /* A real HTML touch target inside WKWebView retains user activation.
             iPad Safari may refuse to open the keyboard from a Flash callback. */
          #keyboard-trigger{
            position:fixed;right:18px;top:150px;z-index:2147483000;
            width:51px;height:51px;border-radius:50%;border:0;
            background:rgba(255,255,255,.98);color:#2877e9;
            box-shadow:0 3px 10px rgba(0,0,0,.2);
            display:grid;place-items:center;font-size:25px;
            cursor:pointer;-webkit-tap-highlight-color:transparent;
            touch-action:manipulation;
          }
          #keyboard-trigger:active{background:#e1edff}
          #keyboard-actions{
            display:none;position:fixed;right:18px;top:211px;z-index:2147483000;
            gap:5px;align-items:center;
          }
          #keyboard-actions button{
            border:0;border-radius:13px;background:rgba(255,255,255,.96);
            color:#1c497e;padding:9px 10px;font-size:13px;font-weight:600;
            box-shadow:0 3px 9px rgba(0,0,0,.17);touch-action:manipulation;
          }
        </style>
        <script>
          window.RufflePlayer=window.RufflePlayer||{};
          window.RufflePlayer.config={
            autoplay:"on",unmuteOverlay:"hidden",splashScreen:false,
            scale:"showAll",forceScale:true,letterbox:"on",salign:"",forceAlign:true,
            allowScriptAccess:true,publicPath:"/ruffle/",
            socketProxy:[{host:"103.91.210.16",port:22973,proxyUrl:"ws://127.0.0.1:32973"}]
          };
        </script><script src="/ruffle/ruffle.js"></script>
        <script src="/ruffle/pvm-compat.js"></script></head>
        <body><div id="game"></div><div id="message">正在载入游戏资源…</div>
        <button id="keyboard-trigger" type="button" title="显示 iPad 键盘"
                aria-label="打开输入键盘">⌨</button>
        <div id="keyboard-actions" aria-label="游戏键盘辅助键">
          <button id="keyboard-backspace" type="button">退格</button>
          <button id="keyboard-enter" type="button">回车</button>
        </div>
        <script>
        (async function(){
          var player,message=document.getElementById("message"),last="";
          function report(x){try{window.webkit.messageHandlers.gameDiagnostics.postMessage("状态："+x)}catch(e){}}
          // Ruffle 0.7.1 creates its own #virtual-keyboard inside an OPEN
          // ShadowRoot, but hides it at top:-100px, 1px, opacity:0.
          // iPad WebKit can reject focus on a completely off-screen input.

          // Use a real document-level input. A fixed-position element inside
          // Ruffle's transformed ShadowRoot was rendered at the top-left on iPad.
          // Keeping this outside Ruffle gives actual viewport-centered placement.
          function keyboardInput(){
            // Keep Ruffle's REAL keyboard input in its ShadowRoot. Moving
            // focus outside the player would lose Flash's focused TextField.
            var p=player||document.querySelector("ruffle-player");
            return p&&p.shadowRoot&&p.shadowRoot.getElementById("virtual-keyboard");
          }
          function gameKey(key,code){
            if(!player)return;
            ["keydown","keyup"].forEach(function(type){
              player.dispatchEvent(new KeyboardEvent(type,{
                key:key,code:code||"",bubbles:true,composed:true
              }));
            });
          }
          var inputShown=true;
          function placeInputDock(){
            // Position the Ruffle input ABSOLUTELY in its own 960x560 player.
            // A CSS 'fixed' input inside the transformed ShadowRoot was
            // erroneously positioned at the iPad's upper-left corner.
          }
          function setDockVisible(visible,reason){
            var input=keyboardInput();
            inputShown=visible;
            if(input){
              if(!visible&&input.getRootNode().activeElement===input){
                input.blur();
              }
              input.style.setProperty("display",visible?"block":"none","important");
            }
            if(reason)report("输入栏："+(visible?"显示":"隐藏")+"；"+reason);
          }
          function pollGameEntry(){
            fetch("/__micro/status",{cache:"no-store"}).then(function(r){return r.json()})
              .then(function(data){
                if(data&&data.enteredGame&&inputShown){
                  setDockVisible(false,"收到进入游戏成功响应");
                }
              }).catch(function(){});
          }
          setInterval(pollGameEntry,2200);
          function prepareKeyboard(){
            var input=keyboardInput();
            if(!input)return null;
            // Unlike fixed positioning, absolute + 50% is relative to
            // Ruffle's #container and remains centered for all iPad sizes.
            var css={
              position:"absolute",left:"50%",top:"8px",right:"auto",bottom:"auto",
              transform:"translateX(-50%)",
              width:"min(420px, calc(100% - 28px))",height:"42px",
              opacity:"1",zIndex:"2147483000",pointerEvents:"auto",
              visibility:"visible",display:inputShown?"block":"none",
              boxSizing:"border-box",background:"rgba(252,254,255,.99)",
              color:"#173653",border:"2px solid #398df0",borderRadius:"12px",
              boxShadow:"0 4px 14px rgba(0,0,0,.25)",
              padding:"6px 12px",fontSize:"16px",fontWeight:"500",
              touchAction:"manipulation"
            };
            Object.keys(css).forEach(function(k){
              input.style.setProperty(k.replace(/[A-Z]/g,function(c){return "-"+c.toLowerCase()}),css[k],"important");
            });
            input.setAttribute("aria-hidden","false");
            input.setAttribute("placeholder","点账号或密码框后，在此输入");
            input.setAttribute("autocomplete","off");
            input.setAttribute("autocorrect","off");
            input.setAttribute("autocapitalize","none");
            input.setAttribute("spellcheck","false");
            if(!input.__shiguangNativeInput){
              input.__shiguangNativeInput=true;
              var composing=false,typed=0,deleted=0,commits=0,lastBackspace=0,lastReturn=0;
              function flush(){
                if(composing)return;
                var value=input.value;
                input.value="";
                if(!value)return;
                for(var char of value){gameKey(char,"");typed++;}
                if(typed===1||typed%12===0)
                  report("键盘统计：已转发字符="+typed+" 退格="+deleted+" 输入法提交="+commits+"（不含实际内容）");
              }
              function special(key){
                var now=performance.now();
                if(key==="Backspace"){
                  if(now-lastBackspace<70)return;
                  lastBackspace=now;deleted++;gameKey("Backspace","Backspace");
                }else if(key==="Enter"){
                  if(now-lastReturn<70)return;
                  lastReturn=now;gameKey("Enter","Enter");
                }
              }
              input.addEventListener("compositionstart",function(){composing=true;},true);
              input.addEventListener("compositionend",function(){
                composing=false;commits++;setTimeout(flush,0);
              },true);
              input.addEventListener("keydown",function(ev){
                ev.stopPropagation();
                if(ev.key==="Backspace"||ev.key==="Enter"){
                  ev.preventDefault();special(ev.key);
                }
              },true);
              input.addEventListener("keyup",function(ev){ev.stopPropagation();},true);
              input.addEventListener("beforeinput",function(ev){
                if(ev.inputType==="deleteContentBackward"||ev.inputType==="insertLineBreak"){
                  ev.preventDefault();ev.stopImmediatePropagation();
                  special(ev.inputType==="deleteContentBackward"?"Backspace":"Enter");
                }
              },true);
              // At-target capture fires before Ruffle's normal bubbling
              // virtualKeyboardInput() handler, preventing duplicate events.
              input.addEventListener("input",function(ev){
                flush();
              },true);
              input.addEventListener("focus",function(){report("键盘：真实输入框获得焦点");},true);
              input.addEventListener("blur",function(){report("键盘：输入框失去焦点");},true);
              report("键盘：保留 Ruffle 内部输入组件，使用相对游戏宽度绝对居中");
            }
            placeInputDock();
            return input;
          }
          function openKeyboard(ev){
            if(ev){ev.preventDefault();ev.stopPropagation();}
            if(prepareKeyboard()){
              setDockVisible(!inputShown,"键盘按钮切换输入栏");
              report("请点击游戏上方正中的白色输入栏（登录成功后自动隐藏）");
            }
          }
          var trigger=document.getElementById("keyboard-trigger");
          trigger.addEventListener("click",openKeyboard);
          function virtualKey(key,code){gameKey(key,code);}
          [["keyboard-backspace","Backspace","Backspace"],
           ["keyboard-enter","Enter","Enter"]].forEach(function(binding){
            var button=document.getElementById(binding[0]);
            button.addEventListener("pointerdown",function(e){if(e.cancelable)e.preventDefault()},{passive:false});
            button.addEventListener("click",function(e){
              e.preventDefault();virtualKey(binding[1],binding[2]);
            });
          });
          var stableViewport=null;
          function fit(){
            var v=window.visualViewport,w0=v?v.width:window.innerWidth,h0=v?v.height:window.innerHeight;
            if(!stableViewport||Math.abs(w0-stableViewport.w)>85){
              stableViewport={w:w0,h:Math.max(h0,window.innerHeight)};
            }else if(h0>stableViewport.h){
              stableViewport.h=h0;
            }
            var w=stableViewport.w,h=stableViewport.h;
            var factor=Math.min(w/960,h/560);
            var pw=Math.max(1,Math.floor(960*factor)),ph=Math.max(1,Math.floor(560*factor));
            document.documentElement.style.setProperty("--game-w",pw+"px");
            document.documentElement.style.setProperty("--game-h",ph+"px");
            var game=document.getElementById("game");
            game.style.height=Math.round(h)+"px";
            game.style.width=Math.round(w)+"px";
            if(player){player.style.width=pw+"px";player.style.height=ph+"px";}
            var state=pw+"×"+ph+"；基准屏幕 "+Math.round(w)+"×"+Math.round(h);
            if(state!==last){last=state;report("稳定屏幕适配："+state);}
            placeInputDock();
          }
          window.addEventListener("resize",fit);
          window.addEventListener("orientationchange",function(){stableViewport=null;dockLast="";fit();});
          if(window.visualViewport)window.visualViewport.addEventListener("resize",fit);
          fit();
          try{
            if(!window.RufflePlayer||!window.RufflePlayer.newest)throw Error("Ruffle JS 未加载");
            player=window.RufflePlayer.newest().createPlayer();
            document.getElementById("game").appendChild(player);fit();prepareKeyboard();
            report("微端式直启：Client.swf（不加载 React 网页）");
            var prepared=null;
            try {
              if(window.ShiguangPVMCompat) {
                prepared=await window.ShiguangPVMCompat(\(json(swfURL)),report);
              } else { report("兼容脚本未加载，启动原始 SWF"); }
            } catch(patchError) {
              report("PVM 兼容补丁异常，回退原版："+String(patchError).slice(0,220));
            }
            var options=prepared
              ? {data:prepared,swfFileName:"Client.swf",base:window.location.origin+"/"}
              : {url:\(json(swfURL)),base:\(json(baseURL))};
            report(prepared ? "PVM 补丁版 SWF 正在进入 Ruffle" : "未启用补丁，使用原版 SWF");
            options.socketProxy=[
              {host:"103.91.210.16",port:22973,proxyUrl:"ws://127.0.0.1:32973"},
              {host:"127.0.0.1",port:22973,proxyUrl:"ws://127.0.0.1:32973"},
              {host:"localhost",port:22973,proxyUrl:"ws://127.0.0.1:32973"}
            ];
            await player.ruffle().load(options);
            message.style.display="none";
          }catch(e){message.textContent="启动失败："+e;report("Ruffle 初始化或载入异常："+String(e).slice(0,220))}
        })();
        </script></body></html>
        """
    }
}

enum ServerError: LocalizedError {
    case missingRuffle
    case invalidLocalPort
    var errorDescription: String? {
        switch self {
        case .missingRuffle: return "应用内缺少 Ruffle 运行文件。"
        case .invalidLocalPort: return "本地 HTTP 端口配置无效。"
        }
    }
}
