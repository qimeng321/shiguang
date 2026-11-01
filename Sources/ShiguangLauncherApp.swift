import SwiftUI
import UniformTypeIdentifiers
import WebKit

@main
struct ShiguangLauncherApp: App {
    @StateObject private var launcher = LauncherModel()

    var body: some Scene {
        WindowGroup {
            LauncherView().environmentObject(launcher)
        }
    }
}

struct LauncherView: View {
    @EnvironmentObject private var launcher: LauncherModel
    @State private var showingImporter = false
    @State private var showingGame = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.indigo)
                Text("拾光号").font(.largeTitle.bold())
                Text("游戏服务器：\(GameSocketBridge.serverHost):\(GameSocketBridge.serverPort)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(launcher.status)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if launcher.isImporting { ProgressView() }

                Button("导入 .srom 资源包") { showingImporter = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(launcher.isImporting)

                if !launcher.entries.isEmpty {
                    Picker("启动文件", selection: $launcher.selectedEntry) {
                        ForEach(launcher.entries, id: \.self) { entry in
                            Text(entry).tag(entry)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 520)

                    Button("启动游戏") { showingGame = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(launcher.selectedEntry.isEmpty)
                }

                Spacer()
                Text("资源包会保存在本机应用数据中。请预留足够空间供导入和解压使用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
            .navigationTitle("启动器")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "srom") ?? .data, .zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { launcher.importPackage(url) }
            case .failure(let error):
                launcher.status = "选择文件失败：\(error.localizedDescription)"
            }
        }
        .fullScreenCover(isPresented: $showingGame) {
            if let root = launcher.gameRoot {
                GameView(root: root, entry: launcher.selectedEntry) {
                    showingGame = false
                }
            }
        }
    }
}

struct GameView: View {
    let root: URL
    let entry: String
    let close: () -> Void
    @State private var server: GameServer?
    @State private var errorText: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let server, let url = server.playURL(for: entry) {
                GameWebView(url: url) { errorText = $0 }
                    .ignoresSafeArea()
            } else if let errorText {
                Text(errorText).foregroundStyle(.white).padding(24)
            } else {
                ProgressView("正在启动…").tint(.white)
            }
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            .padding(14)
            .accessibilityLabel("返回启动器")
        }
        .task {
            do {
                let entryFolder = (entry as NSString).deletingLastPathComponent
                let candidate = root.appendingPathComponent(entryFolder, isDirectory: true)
                let packagedWebApp = FileManager.default.fileExists(
                    atPath: candidate.appendingPathComponent("index.html").path
                )
                let service = try GameServer(root: packagedWebApp ? candidate : root,
                                             packagedWebApp: packagedWebApp)
                for _ in 0..<100 {
                    if service.playURL(for: entry) != nil {
                        server = service
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                errorText = "本机资源服务启动超时。"
            }
            catch { errorText = "启动失败：\(error.localizedDescription)" }
        }
        .onDisappear { server = nil }
    }
}

struct GameWebView: UIViewRepresentable {
    let url: URL
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onError: (String) -> Void
        init(onError: @escaping (String) -> Void) { self.onError = onError }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError("网页加载失败：\(error.localizedDescription)")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError("网页加载失败：\(error.localizedDescription)")
        }
    }
}
