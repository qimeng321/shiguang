import SwiftUI
import UniformTypeIdentifiers
import WebKit
import UIKit

@main
struct ShiguangLauncherApp: App {
    @StateObject private var launcher = LauncherModel()

    var body: some Scene {
        WindowGroup {
            LauncherView()
                .environmentObject(launcher)
                // Files → share/open in 拾光号 is a second route for .srom.
                .onOpenURL { url in launcher.importPackage(url) }
        }
    }
}

// A native "open as copy" document picker accepts files from iCloud Drive,
// local storage and third-party providers. We validate .srom/.zip in the model.
struct PackageDocumentPicker: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        init(onPicked: @escaping (URL) -> Void) { self.onPicked = onPicked }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }
    }
}

struct LauncherView: View {
    @EnvironmentObject private var launcher: LauncherModel
    @State private var showingPicker = false
    @State private var showingImportChoices = false
    @State private var showingLocalFiles = false
    @State private var showingClearConfirmation = false
    @State private var showingGame = false

    private let ink = Color(red: 0.11, green: 0.16, blue: 0.30)
    private let subtleInk = Color(red: 0.42, green: 0.48, blue: 0.60)
    private let blue = Color(red: 0.16, green: 0.40, blue: 0.91)
    private let red = Color(red: 0.88, green: 0.31, blue: 0.37)
    private let green = Color(red: 0.11, green: 0.65, blue: 0.49)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    Image("LauncherArt")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: blue.opacity(0.18), radius: 22, y: 10)
                        .accessibilityHidden(true)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("拾光号")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                        Text("v1.3")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(blue.opacity(0.09), in: Capsule())
                    }
                    .padding(.top, 20)

                    Text("轻装启程 · 重返星际")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(subtleInk)
                        .padding(.top, 7)

                    VStack(spacing: 15) {
                        if geometry.size.width > 500 {
                            HStack(spacing: 14) { importButton; clearButton }
                        } else {
                            VStack(spacing: 12) { importButton; clearButton }
                        }
                        Button {
                            if launcher.canStartGame { showingGame = true }
                        } label: {
                            Label("进入游戏", systemImage: "play.fill")
                                .font(.system(size: 19, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .foregroundStyle(.white)
                                .background(
                                    LinearGradient(colors: [green, Color(red: 0.04, green: 0.51, blue: 0.48)],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                                )
                                .opacity(launcher.canStartGame && !launcher.isImporting ? 1 : 0.46)
                        }
                        .disabled(!launcher.canStartGame || launcher.isImporting)
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 32)

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: launcher.canStartGame ? "checkmark.circle.fill" : "info.circle.fill")
                                .foregroundStyle(launcher.canStartGame ? green : blue)
                            Text(launcher.canStartGame ? "美化包已就绪" : "请先导入美化包")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(ink)
                            Spacer(minLength: 0)
                        }
                        Text(launcher.status)
                            .font(.system(size: 13))
                            .foregroundStyle(subtleInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if launcher.isImporting || launcher.isClearing {
                            ProgressView()
                                .tint(blue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(17)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(blue.opacity(0.09), lineWidth: 1))
                    .padding(.top, 23)

                    Text("支持 .srom / .zip；资源仅保存在本机")
                        .font(.system(size: 12))
                        .foregroundStyle(subtleInk.opacity(0.9))
                        .padding(.top, 18)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, geometry.size.width < 430 ? 25 : 36)
                .frame(maxWidth: 570)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(colors: [Color(red: 0.96, green: 0.97, blue: 1),
                                        Color(red: 0.99, green: 0.97, blue: 0.99),
                                        Color(red: 0.95, green: 0.97, blue: 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
        }
        .confirmationDialog("导入美化包", isPresented: $showingImportChoices,
                            titleVisibility: .visible) {
            Button("从“文件”App 选择 .srom / .zip") { showingPicker = true }
            Button("从拾光号共享文件夹导入") {
                launcher.refreshLocalPackages()
                showingLocalFiles = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("如果系统文件选择器无法选中 .srom，请先在“文件”App 中将它复制到“我的 iPad / iPhone → 拾光号启动器”，再使用第二种方式。")
        }
        .sheet(isPresented: $showingPicker) {
            PackageDocumentPicker { url in
                showingPicker = false
                launcher.importPackage(url)
            }
        }
        .sheet(isPresented: $showingLocalFiles) {
            NavigationStack {
                Group {
                    if launcher.localPackages.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("共享文件夹里还没有美化包")
                                .font(.headline)
                            Text("打开系统“文件”App，在“我的 iPad / iPhone → 拾光号启动器”中放入 .srom 或 .zip 文件，再返回这里刷新。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26)
                            Button("重新扫描") { launcher.refreshLocalPackages() }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        List(launcher.localPackages, id: \.path) { url in
                            Button {
                                showingLocalFiles = false
                                launcher.importPackage(url)
                            } label: {
                                Label(url.lastPathComponent, systemImage: "shippingbox")
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .navigationTitle("选择美化包")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("关闭") { showingLocalFiles = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("刷新") { launcher.refreshLocalPackages() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("确定清除已导入的美化包？", isPresented: $showingClearConfirmation,
                            titleVisibility: .visible) {
            Button("清除美化包", role: .destructive) { launcher.clearPackage() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清除本应用已安装的游戏/美化资源，不能撤销；不会删除“文件”App 中保存的原始 .srom/.zip。")
        }
        .onAppear { launcher.refreshLocalPackages() }
        .fullScreenCover(isPresented: $showingGame) {
            if let root = launcher.gameRoot {
                GameView(root: root, entry: launcher.selectedEntry) { showingGame = false }
            }
        }
    }

    private var importButton: some View {
        Button { showingImportChoices = true } label: {
            Label("导入美化包", systemImage: "square.and.arrow.down.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(colors: [blue, Color(red: 0.25, green: 0.56, blue: 0.98)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
        }
        .disabled(launcher.isImporting || launcher.isClearing)
        .buttonStyle(.plain)
    }

    private var clearButton: some View {
        Button { showingClearConfirmation = true } label: {
            Label("清除美化包", systemImage: "trash")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .foregroundStyle(red)
                .background(red.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(red.opacity(0.18), lineWidth: 1))
        }
        .disabled(launcher.isImporting || launcher.isClearing || !launcher.hasInstalledPackage)
        .buttonStyle(.plain)
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
