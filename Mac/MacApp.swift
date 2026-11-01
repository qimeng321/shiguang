import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

@main
struct ShiguangMacApp: App {
    @StateObject private var launcher = LauncherModel()

    var body: some Scene {
        WindowGroup("拾光号 Mac") {
            MacLauncherView(launcher: launcher)
                .frame(minWidth: 680, minHeight: 530)
                .onOpenURL { launcher.importPackage($0) }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("拾光号") {
                Button("打开导入目录") {
                    LaunchDiagnostics.prepare()
                    NSWorkspace.shared.open(LaunchDiagnostics.importDirectory)
                }
                Button("查看诊断日志") {
                    LaunchDiagnostics.prepare()
                    NSWorkspace.shared.open(LaunchDiagnostics.logURL)
                }
            }
        }
    }
}

struct MacLauncherView: View {
    @ObservedObject var launcher: LauncherModel
    @State private var confirmClear = false
    private let mainBlue = Color(red: 0.19, green: 0.44, blue: 0.89)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.93, green: 0.96, blue: 1),
                         Color(red: 0.97, green: 0.98, blue: 1),
                         Color(red: 0.95, green: 0.94, blue: 0.98)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            ScrollView {
                VStack(spacing: 19) {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 39, weight: .semibold))
                            .foregroundColor(mainBlue)
                            .padding(15)
                            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
                        HStack(spacing: 12) {
                            Text("拾光号").font(.system(size: 32, weight: .bold))
                            Text("Mac 1.0")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(mainBlue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(mainBlue.opacity(0.10), in: Capsule())
                        }
                        Text("重返星际 · Intel 与 Apple 芯片通用")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    VStack(spacing: 13) {
                        HStack(spacing: 12) {
                            Button(action: importFromFinder) {
                                Label("导入 .srom / .zip 美化包", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(mainBlue)
                            .disabled(launcher.isImporting || launcher.isClearing)

                            Button("打开导入目录") {
                                launcher.refreshLocalPackages()
                                LaunchDiagnostics.prepare()
                                NSWorkspace.shared.open(LaunchDiagnostics.importDirectory)
                            }
                            .disabled(launcher.isImporting || launcher.isClearing)
                        }
                        HStack(spacing: 12) {
                            Button {
                                guard let root = launcher.gameRoot else { return }
                                MacGameWindow.shared.open(root: root, entry: launcher.selectedEntry)
                            } label: {
                                Label("进入游戏", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.12, green: 0.60, blue: 0.43))
                            .disabled(!launcher.canStartGame)

                            Button("清除已导入资源", role: .destructive) {
                                confirmClear = true
                            }
                            .disabled(launcher.isImporting || launcher.isClearing || !launcher.hasInstalledPackage)
                        }
                    }
                    VStack(alignment: .leading, spacing: 11) {
                        Label(launcher.canStartGame ? "美化包已就绪" : "资源状态",
                              systemImage: launcher.canStartGame ? "checkmark.circle.fill" : "info.circle")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(launcher.status)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        if launcher.isImporting {
                            HStack {
                                Text(launcher.importPhase)
                                Spacer()
                                Text("\(Int((launcher.importProgress * 100).rounded(.down)))%")
                                    .monospacedDigit()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            ProgressView(value: launcher.importProgress, total: 1)
                                .tint(mainBlue)
                        } else if launcher.isClearing {
                            ProgressView("正在清除资源…")
                        }
                        Divider()
                        Text(launcher.resourceCheckSummary)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        if !launcher.entries.isEmpty {
                            Picker("游戏入口", selection: $launcher.selectedEntry) {
                                ForEach(launcher.entries, id: \.self) { entry in
                                    Text(entry).tag(entry)
                                }
                            }
                            .font(.system(size: 12))
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Button("重新检查资源") { launcher.refreshResourceCheck() }
                        Button("导入目录扫描") {
                            launcher.refreshLocalPackages()
                            if let file = launcher.localPackages.first {
                                launcher.importPackage(file)
                            }
                        }
                        Button("查看诊断日志") {
                            LaunchDiagnostics.prepare()
                            NSWorkspace.shared.open(LaunchDiagnostics.logURL)
                        }
                        Spacer()
                        Text("macOS 12+")
                            .foregroundColor(.secondary)
                    }
                    .font(.system(size: 12))
                    Text("游戏资源仅保存在本机；Mac 版与 iPad 版相互独立。首次启动可能需要在系统安全设置中批准打开。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 37)
                .padding(.vertical, 30)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .alert("清除本机已导入的游戏资源？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) { }
            Button("确定清除", role: .destructive) { launcher.clearPackage() }
        } message: {
            Text("这会删除当前 Mac 版已安装的游戏资源，不能撤销。")
        }
        .onAppear {
            launcher.refreshResourceCheck()
            launcher.refreshLocalPackages()
        }
    }

    private func importFromFinder() {
        let dialog = NSOpenPanel()
        dialog.title = "选择拾光号美化包"
        dialog.message = "请选择 .srom 或 .zip 游戏资源包"
        dialog.allowedContentTypes = [.data, .zip]
        dialog.allowsOtherFileTypes = true
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = false
        dialog.begin { response in
            guard response == .OK, let file = dialog.url else { return }
            launcher.importPackage(file)
        }
    }
}

// A normal, resizable macOS game window—not a full-screen iPad sheet.
final class MacGameWindow: NSObject, NSWindowDelegate {
    static let shared = MacGameWindow()
    private var window: NSWindow?

    func open(root: URL, entry: String) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let screen = NSHostingController(rootView: MacGameView(root: root, entry: entry))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1150, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "拾光号 · Mac 1.0"
        window.minSize = NSSize(width: 850, height: 540)
        window.contentViewController = screen
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct MacGameView: View {
    let root: URL
    let entry: String
    @State private var server: GameServer?
    @State private var errorText: String?
    @State private var reloadID = 0
    @State private var gameStatus = "准备本地资源服务…"
    @State private var isClearing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("拾光号")
                    .font(.system(size: 14, weight: .bold))
                Text(gameStatus)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    reloadID += 1
                    LaunchDiagnostics.log("[Mac] 用户刷新游戏")
                } label: {
                    Label("刷新游戏", systemImage: "arrow.clockwise")
                }
                .disabled(server == nil || isClearing)
                Button {
                    isClearing = true
                    let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
                    WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
                        DispatchQueue.main.async {
                            reloadID += 1
                            isClearing = false
                        }
                    }
                } label: {
                    Label("清理网页缓存", systemImage: "trash")
                }
                .disabled(isClearing)
                Button {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                } label: {
                    Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(Color(NSColor.windowBackgroundColor))
            ZStack {
                Color.black
                if let errorText {
                    Text(errorText)
                        .foregroundColor(.red)
                        .padding(30)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let url = server?.playURL(for: entry) {
                    MacWebView(url: url) { message in
                        gameStatus = message
                    } onError: { message in
                        errorText = message
                    }
                    .id(reloadID)
                } else {
                    ProgressView("正在启动游戏…")
                        .foregroundColor(.white)
                }
            }
        }
        .task {
            guard server == nil else { return }
            LaunchDiagnostics.log("[Mac] 开始进入游戏：\(entry)")
            let actual = root.appendingPathComponent(entry)
            guard FileManager.default.fileExists(atPath: actual.path) else {
                errorText = "未找到游戏入口：\(entry)。请返回启动器重新检查资源。"
                return
            }
            do {
                let folder = (entry as NSString).deletingLastPathComponent
                let candidate = root.appendingPathComponent(folder, isDirectory: true)
                let packaged = FileManager.default.fileExists(
                    atPath: candidate.appendingPathComponent("index.html").path
                )
                let service = try GameServer(root: packaged ? candidate : root,
                                             packagedWebApp: packaged)
                for _ in 0..<120 {
                    if let error = service.startError ?? service.bridgeError {
                        errorText = error
                        return
                    }
                    if service.playURL(for: entry) != nil {
                        server = service
                        gameStatus = "服务器已连接 · 请在游戏内登录"
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                errorText = "本地资源服务或连接代理启动超时，查看 diagnostics.txt。"
            } catch {
                errorText = "游戏启动失败：\(error.localizedDescription)"
            }
        }
        .onDisappear { server = nil }
    }
}

struct MacWebView: NSViewRepresentable {
    let url: URL
    let onStatus: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStatus: onStatus, onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "gameDiagnostics")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .black
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "gameDiagnostics")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onStatus: (String) -> Void
        let onError: (String) -> Void

        init(onStatus: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onStatus = onStatus
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let details = message.body as? String else { return }
            DispatchQueue.main.async {
                if details.hasPrefix("错误：") {
                    self.onError(String(details.dropFirst(3)))
                } else if details.hasPrefix("状态：") {
                    self.onStatus(String(details.dropFirst(3)))
                } else {
                    self.onStatus(details)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.onError(error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.onError(error.localizedDescription) }
        }
    }
}
