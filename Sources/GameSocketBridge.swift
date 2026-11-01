import Foundation
import Network

/// Local WebSocket-to-TCP relay for a browser-based Flash client.
final class GameSocketBridge {
    static let serverHost = "103.91.210.16"
    static let serverPort: UInt16 = 22973
    static let localPort: UInt16 = 32973

    private let queue = DispatchQueue(label: "cn.shiguanghao.launcher.socket")
    private let listener: NWListener
    private var sessions: [UUID: Session] = [:]
    private var acceptedCount = 0
    var hasReceivedClient: Bool { queue.sync { acceptedCount > 0 } }
    // Access state through the listener queue, because the UI polls from the
    // main thread while NWListener updates arrive on `queue`.
    private var readyFlag = false
    private var failureReason: String?
    var isReady: Bool { queue.sync { readyFlag } }
    var failureDescription: String? { queue.sync { failureReason } }

    init() throws {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        options.setClientRequestHandler(queue) { _, _ in
            NWProtocolWebSocket.Response(status: .accept, subprotocol: nil)
        }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        // `requiredLocalEndpoint` plus `on: <same port>` has been observed
        // to produce EINVAL (error 22) when constructing NWListener.
        // Bind to the loopback interface without specifying the port twice.
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.localPort)!)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                LaunchDiagnostics.log("本地 WebSocket 代理就绪，端口：32973")
                self?.readyFlag = true
                self?.failureReason = nil
            case .failed(let error):
                LaunchDiagnostics.log("本地 WebSocket 代理失败：\(error.localizedDescription)")
                self?.readyFlag = false
                self?.failureReason = "本地 WebSocket 代理启动失败 [32973]：\(error.localizedDescription)"
            case .waiting(let error):
                LaunchDiagnostics.log("本地 WebSocket 代理等待：\(error.localizedDescription)")
                self?.readyFlag = false
                self?.failureReason = "本地 WebSocket 代理等待网络 [32973]：\(error.localizedDescription)"
            case .cancelled:
                self?.readyFlag = false
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] webSocket in
            LaunchDiagnostics.log("Flash WebSocket 代理收到新的本地连接")
            guard let self else { webSocket.cancel(); return }
            self.acceptedCount += 1
            let id = UUID()
            let session = Session(webSocket: webSocket, queue: self.queue) { [weak self] in
                self?.sessions.removeValue(forKey: id)
            }
            self.sessions[id] = session
            session.start()
        }
        listener.start(queue: queue)
    }

    deinit {
        listener.cancel()
        sessions.values.forEach { $0.stop() }
    }

    private final class Session {
        private let webSocket: NWConnection
        private let tcp: NWConnection
        private let queue: DispatchQueue
        private let onClose: () -> Void
        private var closed = false
        private var loggedUpstreamBytes = false
        private var loggedDownstreamBytes = false

        init(webSocket: NWConnection, queue: DispatchQueue, onClose: @escaping () -> Void) {
            self.webSocket = webSocket
            self.queue = queue
            self.onClose = onClose
            self.tcp = NWConnection(
                host: NWEndpoint.Host(GameSocketBridge.serverHost),
                port: NWEndpoint.Port(rawValue: GameSocketBridge.serverPort)!,
                using: .tcp
            )
        }

        func start() {
            webSocket.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    LaunchDiagnostics.log("[登录网络] 本地 WebSocket 握手完成")
                case .failed(let error):
                    LaunchDiagnostics.log("[登录网络] 本地 WebSocket 失败：" + error.localizedDescription)
                    self?.stop()
                case .waiting(let error):
                    LaunchDiagnostics.log("[登录网络] 本地 WebSocket 等待：" + error.localizedDescription)
                case .cancelled:
                    self?.stop()
                default: break
                }
            }
            tcp.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    LaunchDiagnostics.log("[登录网络] 远端 TCP 连接成功：" + GameSocketBridge.serverHost + ":" + String(GameSocketBridge.serverPort))
                case .failed(let error):
                    LaunchDiagnostics.log("[登录网络] 远端 TCP 连接失败：" + error.localizedDescription)
                    self?.stop()
                case .waiting(let error):
                    LaunchDiagnostics.log("远端 TCP 游戏服务器等待中：\(error.localizedDescription)")
                case .cancelled:
                    self?.stop()
                default: break
                }
            }
            webSocket.start(queue: queue)
            tcp.start(queue: queue)
            receiveWebSocket()
            receiveTCP()
        }

        func stop() {
            guard !closed else { return }
            closed = true
            webSocket.cancel()
            tcp.cancel()
            onClose()
        }

        private func receiveWebSocket() {
            webSocket.receiveMessage { [weak self] data, context, _, error in
                guard let self, !self.closed else { return }
                if error != nil { self.stop(); return }
                if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata, metadata.opcode == .close {
                    self.stop()
                    return
                }
                guard let data else { self.receiveWebSocket(); return }
                if !self.loggedUpstreamBytes {
                    self.loggedUpstreamBytes = true
                    LaunchDiagnostics.log("[登录网络] 首次 Flash→远端传输：" + String(data.count) + " 字节（不记录内容）")
                }
                self.tcp.send(content: data, completion: .contentProcessed { [weak self] error in
                    if error != nil { self?.stop() }
                    else { self?.receiveWebSocket() }
                })
            }
        }

        private func receiveTCP() {
            tcp.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
                guard let self, !self.closed else { return }
                if error != nil || complete { self.stop(); return }
                guard let data, !data.isEmpty else { self.receiveTCP(); return }
                if !self.loggedDownstreamBytes {
                    self.loggedDownstreamBytes = true
                    LaunchDiagnostics.log("[登录网络] 首次远端→Flash 传输：" + String(data.count) + " 字节（不记录内容）")
                }
                let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
                let context = NWConnection.ContentContext(identifier: "binary", metadata: [metadata])
                self.webSocket.send(content: data, contentContext: context, isComplete: true,
                                    completion: .contentProcessed { [weak self] error in
                    if error != nil { self?.stop() }
                    else { self?.receiveTCP() }
                })
            }
        }
    }
}
