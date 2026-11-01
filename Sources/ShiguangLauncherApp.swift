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

// The custom file type is declared in Info.plist as well.  The broad .data
// fallback handles Files providers that label .srom files as generic data.
private extension UTType {
    static let shiguangPackage = UTType(exportedAs: "cn.shiguanghao.srom", conformingTo: .zip)
}

struct LauncherView: View {
    @EnvironmentObject private var launcher: LauncherModel
    @State private var showingImporter = false
    @State private var showingGame = false

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        Spacer(minLength: 20)

                        Image("LauncherArt")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .accessibilityHidden(true)

                        Text("拾光号")
                            .font(.largeTitle.bold())
                        Text(launcher.status)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if launcher.isImporting {
                            ProgressView("正在处理资源包…")
                                .padding(.vertical, 8)
                        }

                        Button {
                            showingImporter = true
                        } label: {
                            Label("导入 .srom 资源包", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(launcher.isImporting)

                        if !launcher.entries.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("启动文件")
                                    .font(.subheadline.weight(.semibold))
                                Picker("启动文件", selection: $launcher.selectedEntry) {
                                    ForEach(launcher.entries, id: \.self) { entry in
                                        Text(entry).tag(entry)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    showingGame = true
                                } label: {
                                    Label("启动游戏", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity, minHeight: 38)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(launcher.selectedEntry.isEmpty)
                            }
                        }

                        Spacer(minLength: 28)
                        Text("资源包仅保存在当前设备中。请预留足够的存储空间供导入和解压使用。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("拾光号")
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.shiguangPackage, .zip, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    launcher.status = "没有选中文件。"
                    return
                }
                launcher.importPackage(url)
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
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
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
