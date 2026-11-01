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
                        Text("v2.8")
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
                        Divider().opacity(0.35)
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "checkmark.shield")
                                .foregroundStyle(blue)
                            Text(launcher.resourceCheckSummary)
                                .font(.system(size: 12))
                                .foregroundStyle(subtleInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        Text("诊断日志：文件 App → 我的 iPad → 拾光号启动器 → diagnostics.txt")
                            .font(.system(size: 11))
                            .foregroundStyle(subtleInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

                    Text("支持 .srom / .zip；已安装资源保持私有，不占用共享文件夹额外空间")
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
            Text("如果系统文件选择器无法选中 .srom，请先在“文件”App 中将它复制到“我的 iPad / iPhone → 拾光号启动器 → Import”，再使用第二种方式。")
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
                            Text("打开系统“文件”App，在“我的 iPad / iPhone → 拾光号启动器 → Import”中放入 .srom 或 .zip 文件，再返回这里刷新。")
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
        .onAppear {
            launcher.refreshLocalPackages()
            launcher.refreshResourceCheck()
        }
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
    @State private var gameStatus = "正在启动本地游戏服务…"
    @State private var reloadGeneration = 0
    @State private var showingCacheConfirmation = false
    @State private var isClearingWebCache = false
    @State private var showingDiagnostics = false

    // Two non-destructive game controls inspired by the compact xin计划 UI.
    // The underlying .srom remains in Application Support/Game at all times.
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isClearingWebCache {
                ProgressView("正在清理网页缓存…")
                    .foregroundStyle(.white)
                    .tint(.white)
            } else if let server, let url = server.playURL(for: entry) {
                GameWebView(url: url, onStatus: { message in
                    gameStatus = message
                    LaunchDiagnostics.log("网页状态：" + message)
                }, onError: { message in
                    errorText = message
                    LaunchDiagnostics.log("网页错误：" + message)
                })
                .id(reloadGeneration) // recreate WKWebView and Flash, leave HTTP service/resources intact
                .ignoresSafeArea()
            } else if let errorText {
                Text(errorText).foregroundStyle(.white).padding(24)
            } else {
                ProgressView("正在启动…").tint(.white)
            }

            // Preserve the entire viewport for the game. Controls float above it.
            VStack {
                HStack(alignment: .top) {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(width: 48, height: 48)
                            .background(.white.opacity(0.94), in: Circle())
                            .shadow(color: .black.opacity(0.18), radius: 9, y: 3)
                    }
                    .accessibilityLabel("返回拾光号启动器")
                    Spacer()
                    VStack(spacing: 12) {
                        Button(action: reloadGame) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color(red: 0.06, green: 0.50, blue: 0.98))
                                .frame(width: 51, height: 51)
                                .background(.white.opacity(0.97), in: Circle())
                                .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
                        }
                        .disabled(server == nil || isClearingWebCache)
                        .accessibilityLabel("刷新游戏")
                        Button { showingCacheConfirmation = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color(red: 0.60, green: 0.16, blue: 0.80))
                                .frame(width: 51, height: 51)
                                .background(.white.opacity(0.97), in: Circle())
                                .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
                        }
                        .disabled(isClearingWebCache)
                        .accessibilityLabel("清理网页缓存")
                    }
                }
                .padding(.top, 14)
                Spacer(minLength: 12)
                HStack(alignment: .bottom, spacing: 9) {
                    Button { showingDiagnostics.toggle() } label: {
                        Image(systemName: showingDiagnostics ? "waveform.path.ecg.rectangle" : "waveform.path.ecg")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.38), in: Circle())
                    }
                    .accessibilityLabel(showingDiagnostics ? "隐藏诊断状态" : "显示诊断状态")
                    if showingDiagnostics {
                        Text(gameStatus)
                            .lineLimit(3)
                            .font(.system(size: 12, weight: .medium))
                            .textSelection(.enabled)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 18)

            if let errorText {
                VStack {
                    Spacer()
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 57)
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .confirmationDialog("清理游戏网页缓存？", isPresented: $showingCacheConfirmation,
                            titleVisibility: .visible) {
            Button("清理网页缓存并刷新游戏", role: .destructive) { clearWebCache() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅清理本应用 WebKit 的网页磁盘及内存缓存，不删除美化包、已安装游戏资源、账号数据或保存的 diagnostics.txt。")
        }
        .task {
            LaunchDiagnostics.log("进入游戏：\(entry)")
            do {
                let actualSWF = root.appendingPathComponent(entry)
                guard FileManager.default.fileExists(atPath: actualSWF.path) else {
                    errorText = "已安装目录中没有找到游戏入口：\(entry)。请返回首页查看资源检查，再提供 diagnostics.txt。"
                    LaunchDiagnostics.log("游戏启动前检查失败：\(actualSWF.path) 不存在")
                    return
                }
                let entryFolder = (entry as NSString).deletingLastPathComponent
                let candidate = root.appendingPathComponent(entryFolder, isDirectory: true)
                let packagedWebApp = FileManager.default.fileExists(
                    atPath: candidate.appendingPathComponent("index.html").path
                )
                LaunchDiagnostics.log("网页根目录：\(packagedWebApp ? candidate.path : root.path)；原网页模式：\(packagedWebApp)")
                let service = try GameServer(root: packagedWebApp ? candidate : root,
                                             packagedWebApp: packagedWebApp)
                for _ in 0..<100 {
                    if let reason = service.startError ?? service.bridgeError {
                        errorText = reason
                        LaunchDiagnostics.log("游戏启动失败：" + reason)
                        return
                    }
                    if service.playURL(for: entry) != nil {
                        server = service
                        LaunchDiagnostics.log("本地资源服务就绪：\(service.playURL(for: entry)?.absoluteString ?? "未知 URL")")
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                errorText = "本地资源服务或 WebSocket 代理启动超时（HTTP: 18765–18769 / WebSocket: 32973）。请提供错误截图。"
                LaunchDiagnostics.log("游戏启动失败：" + (errorText ?? "未知超时"))
            }
            catch {
                errorText = "本地服务创建失败：\(error.localizedDescription)；请检查 Network 框架监听器参数。"
                LaunchDiagnostics.log("本地服务创建失败：" + error.localizedDescription)
            }
        }
        .onDisappear { server = nil }
    }

    private func reloadGame() {
        guard server != nil && !isClearingWebCache else { return }
        errorText = nil
        gameStatus = "正在刷新游戏…"
        reloadGeneration += 1
        LaunchDiagnostics.log("[游戏控制] 用户点击刷新游戏：重建 WKWebView，保留 .srom 资源和本地 HTTP 服务")
    }

    private func clearWebCache() {
        guard !isClearingWebCache else { return }
        isClearingWebCache = true
        errorText = nil
        gameStatus = "正在清理网页缓存…"
        LaunchDiagnostics.log("[游戏控制] 用户确认清理 WebKit 网页缓存：不会删除 Application Support/Game")
        // Avoid allWebsiteDataTypes(): cookies, localStorage and saved login data are NOT removed.
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            DispatchQueue.main.async {
                self.isClearingWebCache = false
                self.gameStatus = "网页缓存已清理，游戏正在重新加载…"
                self.reloadGeneration += 1
                LaunchDiagnostics.log("[游戏控制] WebKit 内存/磁盘缓存清理完成，已重建 WKWebView；已安装游戏资源未受影响")
            }
        }
    }
}

struct GameWebView: UIViewRepresentable {
    let url: URL
    let onStatus: (String) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.add(context.coordinator, name: "gameDiagnostics")
        let diagnostics = #"""
            (function () {
              function report(message) {
                try { window.webkit.messageHandlers.gameDiagnostics.postMessage(message); } catch (_) {}
              }
              function status(message) { report('状态：' + message); }
              function fail(message) { report('错误：' + message); }
              // Forward a bounded subset of Ruffle warnings/errors to the shared log.
              // This is a diagnostic build; do not forward arbitrary console messages.
              var consoleCount = 0;
              ['warn', 'error'].forEach(function (level) {
                var original = console[level];
                console[level] = function () {
                  if (consoleCount < 60) {
                    var detail = Array.prototype.slice.call(arguments, 0, 4).map(function (value) {
                      try { return String(value).slice(0, 240); } catch (_) { return '[不可显示]'; }
                    }).join(' ');
                    if (/ruffle|avm2|flash|stub|wasm|error|failed|unsupported|exception|bytearray|loader|pvm|version|zlib|inflate|uncompress|警告|失败/i.test(detail)) {
                      consoleCount++;
                      report('运行日志[' + level + ']：' + detail.slice(0, 420));
                    }
                  }
                  return original.apply(console, arguments);
                };
              });
              // Capture Flash trace with bounded output. Observe document rather
              // than documentElement because this script runs at document start.
              var traceCount = 0;
              function attachFlashTrace() {
                var node = document.querySelector('ruffle-player,ruffle-object,ruffle-embed');
                if (!node || node.__shiguangTraceInstalled) return;
                try {
                  var player = typeof node.ruffle === 'function' ? node.ruffle() : node;
                  if (!player || !('traceObserver' in player)) return;
                  player.traceObserver = function (value) {
                    if (++traceCount > 120) return;
                    var line = String(value || '').slice(0, 380);
                    if (/password|passwd|token|session|cookie|authorization|账号|密码|密钥/i.test(line)) return;
                    report('Flash trace：' + line);
                  };
                  node.__shiguangTraceInstalled = true;
                  report('状态：Flash trace 已接入');
                } catch (err) {
                  report('状态：Flash trace 监听错误：' + String(err).slice(0, 120));
                }
              }
              var flashObserver = new MutationObserver(attachFlashTrace);
              flashObserver.observe(document, { childList: true, subtree: true });
              var traceChecks = 0;
              var traceTimer = setInterval(function () {
                attachFlashTrace();
                if (++traceChecks >= 120) {
                  clearInterval(traceTimer);
                  flashObserver.disconnect();
                }
              }, 500);
              // Observe Ruffle runtime progress without collecting packets or credentials.
              function reportPlayerState(label) {
                var node = document.querySelector('ruffle-player,ruffle-object,ruffle-embed');
                if (!node) { status(label + '：未找到 Ruffle 播放器'); return; }
                try {
                  var player = typeof node.ruffle === 'function' ? node.ruffle() : node;
                  var state = player ? String(player.readyState) : '无 API';
                  var playing = player ? String(player.isPlaying) : '未知';
                  var suspended = player && 'suspended' in player ? String(player.suspended) : '未知';
                  status(label + '：readyState=' + state + ' isPlaying=' + playing + ' suspended=' + suspended);
                } catch(e) { fail(label + '：Ruffle 状态读取失败：' + String(e).slice(0, 130)); }
              }
              window.addEventListener('DOMContentLoaded', function () {
                setTimeout(function () { reportPlayerState('启动5秒'); }, 5000);
                setTimeout(function () { reportPlayerState('启动20秒'); }, 20000);
                // Verify the actual Ruffle host position on iPad: this catches
                // future layout regressions without reading any game/account data.
                setTimeout(function () {
                  var host = document.querySelector('ruffle-object,ruffle-player,ruffle-embed,object[data$=".swf"]');
                  if (!host) { status('布局检查：未找到游戏画布'); return; }
                  var rect = host.getBoundingClientRect();
                  var vw = window.innerWidth, vh = window.innerHeight;
                  var cx = rect.left + rect.width / 2, cy = rect.top + rect.height / 2;
                  status('布局检查：画面=' + Math.round(rect.width) + '×' + Math.round(rect.height) +
                    '；中心=' + Math.round(cx) + ',' + Math.round(cy) +
                    '；屏幕=' + vw + '×' + vh +
                    '；偏移=' + Math.round(cx - vw/2) + ',' + Math.round(cy - vh/2));
                }, 8000);
              });
              window.addEventListener('error', function (event) {
                if (event.message) fail('网页脚本错误：' + event.message);
                else if (event.target && (event.target.src || event.target.href))
                  fail('资源加载失败：' + (event.target.src || event.target.href));
              }, true);
              window.addEventListener('unhandledrejection', function (event) {
                fail('网页执行失败：' + String(event.reason));
              });
              window.addEventListener('DOMContentLoaded', function () {
                status('HTML 已加载，等待游戏脚本与 Flash…');
                if (window.location.pathname === '/') {
                  ['/assets/index.js', '/assets/nieo_wasm_core_bg.wasm', '/Client.swf', '/ruffle/ruffle.js', '/config/doorConfig.xml', '/resource/main_resource.swf', '/config/ServerR.xml', '/login/Login.swf', '/version.swf'].forEach(function (path) {
                    fetch(path, { method: 'HEAD', cache: 'no-store' })
                      .then(function (response) { report('资源检测：' + path + ' → HTTP ' + response.status); })
                      .catch(function (error) { fail('资源请求失败：' + path + '；' + String(error)); });
                  });
                }
                var checks = 0, previous = '';
                var timer = setInterval(function () {
                  var ruffle = !!window.RufflePlayer;
                  var player = document.querySelector('ruffle-player,ruffle-object,ruffle-embed');
                  var swf = document.querySelector('object[data$=".swf"],embed[src$=".swf"]');
                  var video = document.querySelector('video[src$="/video.mp4"]');
                  var summary = 'Ruffle=' + (ruffle ? '已载入' : '未载入') +
                    '；Flash=' + (player ? '已接管' : (swf ? '待接管' : '未创建')) +
                    '；启动遮罩=' + (video ? '存在' : '已关闭');
                  if (summary !== previous) { status(summary); previous = summary; }
                  if (++checks >= 15) {
                    clearInterval(timer);
                    if (!player && swf) fail('检测到 Flash 对象，但 Ruffle 未接管；请查看游戏启动日志。');
                  }
                }, 1000);
              });
            })();
            """#
        configuration.userContentController.addUserScript(
            WKUserScript(source: diagnostics, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
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
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "gameDiagnostics")
    }
    func makeCoordinator() -> Coordinator { Coordinator(onStatus: onStatus, onError: onError) }

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
            if details.hasPrefix("状态：") { onStatus(String(details.dropFirst(3))) }
            else if details.hasPrefix("错误：") { onError(String(details.dropFirst(3))) }
            else { onStatus(details) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onStatus("网页主文档已打开，检查启动脚本与服务响应…")
            webView.evaluateJavaScript("({title:document.title,body:(document.body?.innerText||'').slice(0,180), scripts:[...document.scripts].map(s=>s.getAttribute('src')).filter(Boolean).slice(0,8), ruffle:!!window.RufflePlayer})") { [weak self] result, error in
                if let error {
                    self?.onError("网页状态读取失败：" + error.localizedDescription)
                } else if let data = result as? [String: Any] {
                    self?.onStatus("页面诊断：" + String(describing: data))
                    if let body = data["body"] as? String, body.contains("Invalid entry") || body.contains("游戏资源入口不存在") {
                        self?.onError("加载到错误页面，而不是游戏：" + body)
                    }
                }
            }
        }
        private func reportNavigationError(_ error: Error, webView: WKWebView) {
            let nsError = error as NSError
            let requestURL = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
                ?? webView.url?.absoluteString ?? "未知地址"
            onError("网页加载失败 [\(nsError.domain):\(nsError.code)] \(nsError.localizedDescription)\n请求地址：\(requestURL)")
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportNavigationError(error, webView: webView)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportNavigationError(error, webView: webView)
        }
    }
}
