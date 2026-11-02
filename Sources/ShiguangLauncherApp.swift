import SwiftUI
import UniformTypeIdentifiers
import WebKit
import UIKit

@main
struct ShiguangLauncherApp: App {
    @StateObject private var launcher = LauncherModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LauncherView()
                .environmentObject(launcher)
                // Files → share/open in 拾光号 is a second route for .srom.
                .onOpenURL { url in launcher.importPackage(url) }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        LaunchDiagnostics.markState("app-active", detail: "应用回到前台")
                    case .inactive:
                        LaunchDiagnostics.markState("app-inactive", detail: "切换中、控制中心或来电均可能触发")
                    case .background:
                        LaunchDiagnostics.markState("app-background", detail: "应用进入后台；这不等于闪退")
                    @unknown default:
                        break
                    }
                }
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

// Kept in the existing Swift source file so the Xcode target needs no changes.
enum GameQualityPreset: String, CaseIterable, Identifiable {
    case saving, balanced, ultra
    var id: String { rawValue }
    var title: String {
        switch self {
        case .saving: return "省电"
        case .balanced: return "均衡"
        case .ultra: return "高清"
        }
    }
    var detail: String {
        switch self {
        case .saving: return "降低渲染负担，适合长时间游玩"
        case .balanced: return "兼顾清晰度与功耗，推荐日常使用"
        case .ultra: return "优先显示效果，可能更容易发热"
        }
    }
    var ruffleQuality: String {
        switch self {
        case .saving: return "medium"
        case .balanced: return "high"
        case .ultra: return "best"
        }
    }
    static let defaultsKey = "shiguang.qualityPreset"
    static var saved: GameQualityPreset {
        GameQualityPreset(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .balanced
    }
}

// A scheduling ceiling, not a Flash movie frameRate override.
enum GameFrameCapPreset: String, CaseIterable, Identifiable {
    case unlimited, fps60, fps30
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unlimited: return "不限制"
        case .fps60: return "最高 60"
        case .fps30: return "最高 30"
        }
    }
    var fpsLimit: Int {
        switch self {
        case .unlimited: return 0
        case .fps60: return 60
        case .fps30: return 30
        }
    }
    var description: String {
        switch self {
        case .unlimited: return "默认，跟随系统及 Flash 原始运行节奏"
        case .fps60: return "尝试把浏览器动画帧调度限制在每秒最多约 60 次"
        case .fps30: return "尝试减少动画渲染频率，以降低发热和耗电"
        }
    }
    static let defaultsKey = "shiguang.maxFrameRate"
    static var saved: GameFrameCapPreset {
        GameFrameCapPreset(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .unlimited
    }
}

struct LauncherView: View {
    @EnvironmentObject private var launcher: LauncherModel
    @State private var showingPicker = false
    @State private var showingImportChoices = false
    @State private var showingLocalFiles = false
    @State private var showingClearConfirmation = false
    @State private var showingGame = false
    @AppStorage(GameQualityPreset.defaultsKey) private var qualityPreset = GameQualityPreset.balanced.rawValue
    @AppStorage(GameFrameCapPreset.defaultsKey) private var frameCapPreset = GameFrameCapPreset.unlimited.rawValue

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
                        Text("正式版 1.02")
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

                    VStack(spacing: 12) {
                        qualityPicker
                        frameCapPicker
                    }
                    .padding(.top, 23)

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
                    .padding(.top, 19)

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: launcher.isImporting ? "arrow.down.circle.fill" :
                                  (launcher.lastImportFailed ? "xmark.octagon.fill" :
                                  (launcher.canStartGame ? "checkmark.circle.fill" : "info.circle.fill")))
                                .foregroundStyle(launcher.lastImportFailed ? red :
                                                 (launcher.canStartGame && !launcher.isImporting ? green : blue))
                            Text(launcher.isImporting ? "正在安装美化包" :
                                 (launcher.lastImportFailed ? "本次导入失败，请重新选择" :
                                  (launcher.canStartGame ? "美化包已就绪" :
                                   (launcher.hasInstalledPackage ? "美化包校验未通过" : "请先导入美化包"))))
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
                            Image(systemName: launcher.isInstalledValidated ?
                                  "checkmark.shield" : "exclamationmark.shield")
                                .foregroundStyle(launcher.isInstalledValidated ? green : red)
                            Text(launcher.resourceCheckSummary)
                                .font(.system(size: 12))
                                .foregroundStyle(subtleInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        if launcher.isImporting {
                            HStack {
                                Text(launcher.importPhase)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ink)
                                Spacer()
                                Text("\(Int((launcher.importProgress * 100).rounded(.down)))%")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(blue)
                            }
                            ProgressView(value: launcher.importProgress, total: 1.0)
                                .progressViewStyle(.linear)
                                .tint(blue)
                                .accessibilityLabel("美化包导入实际进度")
                        } else if launcher.isClearing {
                            ProgressView("正在清除美化包…")
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

                    // One-tap log sharing is useful for diagnosing game issues,
                    // without displaying a permanent diagnostics overlay.
                    ShareLink(item: LaunchDiagnostics.logURL) {
                        Label("反馈问题", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(subtleInk)
                    }
                    .accessibilityLabel("分享拾光号故障日志")
                    .padding(.top, 14)

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
        .alert("美化包导入失败", isPresented: Binding(
            get: { launcher.importFailureMessage != nil },
            set: { if !$0 { launcher.importFailureMessage = nil } }
        )) {
            Button("重新选择美化包") {
                launcher.importFailureMessage = nil
                showingImportChoices = true
            }
            Button("稍后再试", role: .cancel) { launcher.importFailureMessage = nil }
        } message: {
            Text(launcher.importFailureMessage ?? "导入失败，请检查资源包后重试。")
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

    private var frameCapPicker: some View {
        let current = GameFrameCapPreset(rawValue: frameCapPreset) ?? .unlimited
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "speedometer")
                    .foregroundStyle(blue)
                Text("最高帧率")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ink)
                Spacer()
                Text(current.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(blue)
            }
            Picker("最高帧率", selection: $frameCapPreset) {
                ForEach(GameFrameCapPreset.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("最高帧率限制")
            Text(current.description)
                .font(.system(size: 12))
                .foregroundStyle(subtleInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("实验性帧调度限制，不修改游戏原始帧率。选择后重新进入游戏生效。")
                .font(.system(size: 11))
                .foregroundStyle(subtleInk.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(blue.opacity(0.10), lineWidth: 1))
    }

    private var qualityPicker: some View {
        let current = GameQualityPreset(rawValue: qualityPreset) ?? .balanced
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(blue)
                Text("游戏画质")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ink)
                Spacer()
                Text(current.title + "模式")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(blue)
            }
            Picker("游戏画质", selection: $qualityPreset) {
                ForEach(GameQualityPreset.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("游戏画质档位")
            Text(current.detail)
                .font(.system(size: 12))
                .foregroundStyle(subtleInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("进入游戏时生效 · 自动记住上次选择")
                .font(.system(size: 11))
                .foregroundStyle(subtleInk.opacity(0.85))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(blue.opacity(0.10), lineWidth: 1))
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
    @State private var reloadGeneration = 0
    @State private var showingCacheConfirmation = false
    @State private var isClearingWebCache = false
    @State private var toolsExpanded = false
    @State private var toolMenuGeneration = 0
    @State private var controlGeneration = 0
    @State private var controlAction = ""
    @State private var virtualMouseEnabled = false
    @State private var fpsEnabled = false
    // Saved across WebView reloads; off by default for normal click speed.
    @AppStorage("shiguang.delayedTap103") private var delayedTapEnabled = false

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
                GameWebView(url: url, controlGeneration: controlGeneration,
                            controlAction: controlAction, delayedTapEnabled: delayedTapEnabled,
                            onStatus: { message in
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
                    // Fold the iPad utilities into one compact dropdown.
                    VStack(alignment: .trailing, spacing: 9) {
                        Button(action: toggleToolMenu) {
                            Image(systemName: toolsExpanded ? "xmark" : "ellipsis")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(Color(red: 0.12, green: 0.35, blue: 0.66))
                                .frame(width: 46, height: 46)
                                .background(.white.opacity(0.9), in: Circle())
                                .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                        }
                        .accessibilityLabel(toolsExpanded ? "收起游戏工具" : "展开游戏工具")
                        if toolsExpanded {
                            VStack(alignment: .leading, spacing: 3) {
                                gameTool("keyboard", "输入键盘") {
                                    sendControl("toggleKeyboard")
                                }
                                gameTool("cursorarrow", virtualMouseEnabled ? "关闭精准鼠标" : "精准鼠标") {
                                    virtualMouseEnabled.toggle()
                                    sendControl(virtualMouseEnabled ? "enableMouse" : "disableMouse")
                                }
                                if virtualMouseEnabled {
                                    gameTool("crosshair", "准星归中") {
                                        sendControl("resetCursor")
                                    }
                                    gameTool("gauge", "切换鼠标速度") {
                                        sendControl("cycleSpeed")
                                    }
                                }
                                gameTool(delayedTapEnabled ? "checkmark.circle.fill" : "hand.tap",
                                         delayedTapEnabled ? "触屏延迟：开" : "触屏延迟：关") {
                                    delayedTapEnabled.toggle()
                                    LaunchDiagnostics.log("[触控辅助] 手指直接点按及精准鼠标延迟抬起：" + (delayedTapEnabled ? "开启" : "关闭"))
                                }
                                gameTool("speedometer", fpsEnabled ? "隐藏刷新率" : "显示刷新率") {
                                    fpsEnabled.toggle()
                                    sendControl("toggleFPS")
                                }
                                Divider().padding(.vertical, 3)
                                gameTool("arrow.clockwise", "刷新游戏") {
                                    collapseToolMenu()
                                    reloadGame()
                                }
                                .disabled(server == nil || isClearingWebCache)
                                gameTool("trash", "清理缓存") {
                                    collapseToolMenu()
                                    showingCacheConfirmation = true
                                }
                                .disabled(isClearingWebCache)
                            }
                            .padding(8)
                            .frame(width: 168)
                            .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 15))
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: toolsExpanded)
                }
                .padding(.top, 14)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 18)

            if let errorText {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                        if server != nil && !isClearingWebCache {
                            Button("重新加载游戏") { reloadGame() }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
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
        .onDisappear {
            LaunchDiagnostics.markState("game-view-closed", detail: "SwiftUI 游戏视图正常关闭")
            server = nil
        }
    }

    private func gameTool(_ icon: String, _ label: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.13, green: 0.29, blue: 0.48))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func sendControl(_ action: String) {
        guard server != nil else { return }
        controlAction = action
        controlGeneration += 1
        LaunchDiagnostics.log("[触控辅助] 调用：" + action)
        collapseToolMenu()
    }

    private func toggleToolMenu() {
        toolMenuGeneration += 1
        withAnimation(.easeInOut(duration: 0.18)) { toolsExpanded.toggle() }
        guard toolsExpanded else { return }
        let generation = toolMenuGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard toolsExpanded && toolMenuGeneration == generation else { return }
            withAnimation(.easeInOut(duration: 0.18)) { toolsExpanded = false }
        }
    }

    private func collapseToolMenu() {
        toolMenuGeneration += 1
        withAnimation(.easeInOut(duration: 0.18)) { toolsExpanded = false }
    }

    private func reloadGame() {
        guard server != nil && !isClearingWebCache else { return }
        errorText = nil
        virtualMouseEnabled = false
        fpsEnabled = false
        reloadGeneration += 1
        LaunchDiagnostics.log("[游戏控制] 用户点击刷新游戏：重建 WKWebView，保留 .srom 资源和本地 HTTP 服务")
    }

    private func clearWebCache() {
        guard !isClearingWebCache else { return }
        isClearingWebCache = true
        errorText = nil
        virtualMouseEnabled = false
        LaunchDiagnostics.log("[游戏控制] 用户确认清理 WebKit 网页缓存：不会删除 Application Support/Game")
        // Avoid allWebsiteDataTypes(): cookies, localStorage and saved login data are NOT removed.
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            DispatchQueue.main.async {
                self.isClearingWebCache = false
                self.reloadGeneration += 1
                LaunchDiagnostics.log("[游戏控制] WebKit 内存/磁盘缓存清理完成，已重建 WKWebView；已安装游戏资源未受影响")
            }
        }
    }
}

struct GameWebView: UIViewRepresentable {
    let url: URL
    let controlGeneration: Int
    let controlAction: String
    let delayedTapEnabled: Bool
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
              // SWF map progress is drawn INTO canvas, so cannot read its 100%
              // label from DOM. This only measures JS/animation responsiveness.
              var heartbeatFrames = 0;
              function heartbeatFrame(ts) {
                heartbeatFrames++;
                requestAnimationFrame(heartbeatFrame);
              }
              requestAnimationFrame(heartbeatFrame);
              setInterval(function () {
                if (document.hidden) return;
                var frames = heartbeatFrames;
                heartbeatFrames = 0;
                var host = document.querySelector('ruffle-player,ruffle-object,ruffle-embed');
                var ready = '未知', playing = '未知', canvas = '未知';
                try {
                  if (host) {
                    var player = typeof host.ruffle === 'function' ? host.ruffle() : host;
                    ready = String(player && player.readyState);
                    playing = String(player && player.isPlaying);
                    var c = host.shadowRoot && host.shadowRoot.querySelector('canvas');
                    if (c) canvas = c.width + 'x' + c.height;
                  }
                } catch (_) {}
                report('心跳：JS线程响应；5秒动画帧=' + frames +
                  '；Ruffle=' + ready + '/' + playing + '；Canvas=' + canvas);
              }, 5000);
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
              var traceCount = 0, traceObserver = null, traceTimer = null, traceAttached = false;
              function attachFlashTrace() {
                if (traceAttached) return;
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
                  traceAttached = true;
                  // Diagnostics must not watch the entire DOM for the rest
                  // of a long game session after the player is available.
                  if (traceObserver) { traceObserver.disconnect(); traceObserver = null; }
                  if (traceTimer !== null) { clearInterval(traceTimer); traceTimer = null; }
                  report('状态：Flash trace 已接入');
                } catch (err) {
                  report('状态：Flash trace 监听错误：' + String(err).slice(0, 120));
                }
              }
              traceObserver = new MutationObserver(attachFlashTrace);
              traceObserver.observe(document, { childList: true, subtree: true });
              var traceChecks = 0;
              traceTimer = setInterval(function () {
                attachFlashTrace();
                if (++traceChecks >= 120) {
                  clearInterval(traceTimer); traceTimer = null;
                  if (traceObserver) { traceObserver.disconnect(); traceObserver = null; }
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
        // Make the choice available before Ruffle's asynchronous startup.
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.__shiguangDelayedTapChoice = \(delayedTapEnabled ? "true" : "false");",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.lastControlGeneration = controlGeneration
        context.coordinator.lastDelayedTapEnabled = delayedTapEnabled
        webView.navigationDelegate = context.coordinator
        // Opaque backing matches the always-black Flash stage and avoids
        // an unnecessary transparent layer during long GPU-heavy sessions.
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastDelayedTapEnabled != delayedTapEnabled {
            context.coordinator.lastDelayedTapEnabled = delayedTapEnabled
            let value = delayedTapEnabled ? "true" : "false"
            webView.evaluateJavaScript(
                "window.__shiguangDelayedTapChoice=\(value); window.ShiguangControls && window.ShiguangControls.setDelayedTap(\(value));"
            ) { _, error in
                if let error { LaunchDiagnostics.log("[触控辅助] 延迟点按设置异常：" + error.localizedDescription) }
            }
        }
        guard context.coordinator.lastControlGeneration != controlGeneration else { return }
        context.coordinator.lastControlGeneration = controlGeneration
        let allowed = ["toggleKeyboard", "enableMouse", "disableMouse",
                       "resetCursor", "cycleSpeed", "toggleFPS"]
        guard allowed.contains(controlAction) else { return }
        let js = "window.ShiguangControls && window.ShiguangControls." + controlAction + "()"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                LaunchDiagnostics.log("[触控辅助] 指令执行异常：" + error.localizedDescription)
            }
        }
    }
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopHeartbeatWatchdog()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "gameDiagnostics")
    }
    func makeCoordinator() -> Coordinator { Coordinator(onStatus: onStatus, onError: onError) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastControlGeneration = 0
        var lastDelayedTapEnabled = false
        private var navigationCount = 0
        private var lastJSHeartbeat = Date()
        private var lastSavedHeartbeat = Date.distantPast
        private var didWarnStall = false
        private var heartbeatWatchdog: Timer?
        let onStatus: (String) -> Void
        let onError: (String) -> Void
        init(onStatus: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onStatus = onStatus
            self.onError = onError
        }
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let details = message.body as? String else { return }
            if details.hasPrefix("心跳：") {
                lastJSHeartbeat = Date()
                if didWarnStall {
                    didWarnStall = false
                    LaunchDiagnostics.markState("js-heartbeat-recovered",
                        detail: "心跳恢复：" + String(details.prefix(120)))
                }
                if Date().timeIntervalSince(lastSavedHeartbeat) >= 15 {
                    lastSavedHeartbeat = Date()
                    LaunchDiagnostics.markState("js-heartbeat-ok", detail: String(details.prefix(160)))
                }
                return
            }
            if details.hasPrefix("状态：") { onStatus(String(details.dropFirst(3))) }
            else if details.hasPrefix("错误：") { onError(String(details.dropFirst(3))) }
            else { onStatus(details) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame?.isMainFrame == true {
                let path = navigationAction.request.url?.path ?? "未知"
                LaunchDiagnostics.log("[页面生命周期] 主框架请求：\(path)，方式=\(navigationAction.navigationType.rawValue)")
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            navigationCount += 1
            stopHeartbeatWatchdog()
            let path = webView.url?.path ?? "未知"
            LaunchDiagnostics.markState("game-page-loading",
                detail: "主框架第\(navigationCount)次导航：\(path)")
            LaunchDiagnostics.log("[页面生命周期] 主框架开始第\(navigationCount)次导航：\(path)")
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            stopHeartbeatWatchdog()
            LaunchDiagnostics.markState("webcontent-terminated",
                detail: "WebKit 内容进程终止；不等于网络连接断开")
            LaunchDiagnostics.log("[严重诊断] WebKit WebContent 进程终止；可能是内存压力/渲染进程崩溃。保持现场，等待用户点击重新加载。")
            onError("游戏网页进程已终止，可能存在内存压力或渲染异常。点击「重新加载游戏」继续；可导出 diagnostics.txt 排查。")
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            startHeartbeatWatchdog()
            LaunchDiagnostics.markState("game-page-loaded",
                detail: "主框架 HTML 导航完成，等待 SWF 初始化")
            let value = lastDelayedTapEnabled ? "true" : "false"
            webView.evaluateJavaScript("window.__shiguangDelayedTapChoice=\(value); window.ShiguangControls && window.ShiguangControls.setDelayedTap(\(value));") { _, _ in }
            LaunchDiagnostics.log("[页面生命周期] 主框架完成第\(navigationCount)次导航：\(webView.url?.path ?? "未知")")
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
        func stopHeartbeatWatchdog() {
            heartbeatWatchdog?.invalidate()
            heartbeatWatchdog = nil
        }
        private func startHeartbeatWatchdog() {
            stopHeartbeatWatchdog()
            lastJSHeartbeat = Date()
            lastSavedHeartbeat = .distantPast
            didWarnStall = false
            heartbeatWatchdog = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self, UIApplication.shared.applicationState == .active else { return }
                let gap = Int(Date().timeIntervalSince(self.lastJSHeartbeat))
                if gap >= 16 && !self.didWarnStall {
                    self.didWarnStall = true
                    LaunchDiagnostics.markState("suspected-web-freeze",
                        detail: "主页面心跳连续约\(gap)秒未响应；可能 JS 卡死或 WebKit 被暂停，并非确诊崩溃")
                }
            }
        }
        private func reportNavigationError(_ error: Error, webView: WKWebView) {
            stopHeartbeatWatchdog()
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
