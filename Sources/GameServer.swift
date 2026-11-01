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
                // Only expose a URL once the socket is actually accepting traffic.
                self.readyHTTPPort = portNumber
                self.failureMessage = nil
            case .failed(let error):
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
        components.path = packagedWebApp ? "/" : "/index.html"
        if !packagedWebApp { components.queryItems = [URLQueryItem(name: "entry", value: entry)] }
        return components.url
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self, error == nil, let data,
                  let request = String(data: data, encoding: .utf8),
                  let line = request.components(separatedBy: "\r\n").first else {
                connection.cancel()
                return
            }
            self.respond(to: line, connection: connection)
        }
    }

    private func respond(to line: String, connection: NWConnection) {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD",
              let components = URLComponents(string: "http://127.0.0.1\(parts[1])") else {
            sendText("Bad Request", status: 400, connection: connection)
            return
        }
        let headOnly = parts[0] == "HEAD"
        let path = components.path
        // The original .srom web app creates a Flash <object> in React.
        // WKWebView cannot render Flash without a polyfill. Serve our bundled
        // Ruffle files even when the package contains its own index.html.
        if path.hasPrefix("/ruffle/") {
            serve(relative: String(path.dropFirst(8)), below: ruffle, headOnly: headOnly, connection: connection)
            return
        }
        if packagedWebApp {
            let relative = path == "/" ? "index.html" : String(path.dropFirst())
            if relative == "index.html" {
                servePackagedIndex(headOnly: headOnly, connection: connection)
            } else {
                serve(relative: relative, below: root, headOnly: headOnly, connection: connection)
            }
            return
        }
        if path == "/index.html" || path == "/" {
            let entry = components.queryItems?.first(where: { $0.name == "entry" })?.value ?? ""
            guard let file = safeFile(entry, below: root),
                  file.pathExtension.lowercased() == "swf" else {
                sendText("Invalid entry", status: 400, connection: connection)
                return
            }
            let urlPath = "/game/" + entry.split(separator: "/").map {
                String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            }.joined(separator: "/")
            let basePath = (urlPath as NSString).deletingLastPathComponent + "/"
            let html = page(swfURL: urlPath, baseURL: basePath)
            send(data: Data(html.utf8), mime: "text/html; charset=utf-8", headOnly: headOnly, connection: connection)
            return
        }
        if path.hasPrefix("/game/") {
            serve(relative: String(path.dropFirst(6)), below: root, headOnly: headOnly, connection: connection)
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
        <script>
          window.RufflePlayer = window.RufflePlayer || {};
          window.RufflePlayer.config = Object.assign({}, window.RufflePlayer.config || {}, {
            publicPath: "/ruffle/",
            polyfills: true,
            autoplay: "on",
            unmuteOverlay: "visible",
            allowScriptAccess: true,
            socketProxy: [{
              host: "103.91.210.16",
              port: 22973,
              proxyUrl: "ws://127.0.0.1:32973"
            }]
          });
        </script>
        <script src="/ruffle/ruffle.js"></script>
        """#
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

    private func serve(relative: String, below base: URL, headOnly: Bool, connection: NWConnection) {
        guard let file = safeFile(relative, below: base),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: file) else {
            sendText("Not Found", status: 404, connection: connection)
            return
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mime(for: file))\r\nContent-Length: \(size.uint64Value)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            if error != nil || headOnly {
                try? handle.close()
                connection.cancel()
            } else {
                self?.stream(handle, to: connection)
            }
        })
    }

    private func stream(_ handle: FileHandle, to connection: NWConnection) {
        guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.stream(handle, to: connection)
            } else {
                try? handle.close()
                connection.cancel()
            }
        })
    }

    private func sendText(_ text: String, status: Int, connection: NWConnection) {
        send(data: Data(text.utf8), mime: "text/plain; charset=utf-8", status: status, headOnly: false, connection: connection)
    }

    private func send(data: Data, mime: String, status: Int = 200, headOnly: Bool, connection: NWConnection) {
        let reason = status == 200 ? "OK" : status == 400 ? "Bad Request" : "Not Found"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(mime)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + (headOnly ? Data() : data), completion: .contentProcessed { _ in
            connection.cancel()
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

    private func page(swfURL: String, baseURL: String) -> String {
        func json(_ value: String) -> String {
            let data = try! JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed])
            let array = String(data: data, encoding: .utf8)!
            return String(array.dropFirst().dropLast())
        }
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <style>
            html, body, #game { margin: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
            #message { position: fixed; top: 45%; left: 5%; width: 90%; color: white; text-align: center; font: 16px sans-serif; }
            ruffle-player { width: 100%; height: 100%; display: block; }
          </style>
          <script>window.RufflePlayer = window.RufflePlayer || {};
          window.RufflePlayer.config = { autoplay: "on", unmuteOverlay: "visible", publicPath: "/ruffle/" };</script>
          <script src="/ruffle/ruffle.js"></script>
        </head>
        <body>
          <div id="game"></div><div id="message">正在加载游戏…</div>
          <script>
            const message = document.getElementById("message");
            try {
              const ruffle = window.RufflePlayer.newest();
              const player = ruffle.createPlayer();
              document.getElementById("game").appendChild(player);
              player.ruffle().load({ url: \(json(swfURL)), base: \(json(baseURL)) })
                .then(() => { message.style.display = "none"; })
                .catch(error => { message.textContent = "游戏加载失败：" + error; });
            } catch (error) { message.textContent = "Ruffle 启动失败：" + error; }
          </script>
        </body>
        </html>
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
