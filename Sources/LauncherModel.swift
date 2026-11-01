import Foundation
import ZIPFoundation

// A small, visible shared folder for imports and diagnostics. Installed assets
// remain under Application Support/Game and are NEVER duplicated in Documents.
enum LaunchDiagnostics {
    private static let fileQueue = DispatchQueue(label: "cn.shiguanghao.launcher.diagnostics")
    private static let maxLogBytes: UInt64 = 1_000_000
    private static var missingResourceCount = 0

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var importDirectory: URL {
        documents.appendingPathComponent("Import", isDirectory: true)
    }
    static var logURL: URL {
        documents.appendingPathComponent("diagnostics.txt")
    }

    // Prepare synchronously so the folder becomes visible in Files immediately
    // after app launch, not only after an import or a successful game start.
    static func prepare() {
        fileQueue.sync { prepareUnlocked() }
    }

    static func log(_ message: String) {
        fileQueue.async {
            prepareUnlocked()
            appendUnlocked(message)
        }
    }

    // Avoid thousands of missing-asset requests flooding the log on a broken
    // Flash page. Keep the first 100 and report that further 404s were omitted.
    static func missingResource(_ relative: String) {
        fileQueue.async {
            prepareUnlocked()
            if missingResourceCount < 100 {
                appendUnlocked("HTTP 404：资源缺失 " + relative)
            } else if missingResourceCount == 100 {
                appendUnlocked("HTTP 404：缺失资源请求过多，其余不再逐条记录")
            }
            missingResourceCount += 1
        }
    }

    private static func prepareUnlocked() {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
            let instructions = documents.appendingPathComponent("使用说明.txt")
            if !manager.fileExists(atPath: instructions.path) {
                let text = """
                拾光号启动器 - 共享文件夹

                Import/：可放入 .srom 或 .zip 美化包，在启动器的“导入美化包”里选择从共享文件夹导入。
                diagnostics.txt：记录游戏启动、资源检查、网页脚本和本地资源服务的诊断信息。

                已安装的完整游戏资源存放在应用私有的 Application Support/Game/ 中；
                不会复制到这里，也不要为了显示文件夹而重新导入 2.88GB 资源。
                删除这里的诊断日志或导入文件不会删除已安装的游戏资源。
                """
                try text.write(to: instructions, atomically: true, encoding: .utf8)
            }
            if !manager.fileExists(atPath: logURL.path) {
                let header = "拾光号启动器诊断日志\n本文件不含游戏资源；记录仅用于定位黑屏。\n\n"
                try header.write(to: logURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Log is best-effort; it must never prevent importing or launching.
            NSLog("[Shiguang] 创建共享目录失败：%@", error.localizedDescription)
        }
    }

    private static func appendUnlocked(_ message: String) {
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: logURL.path)[.size]) as? NSNumber,
           size.uint64Value > maxLogBytes {
            let previous = documents.appendingPathComponent("diagnostics-previous.txt")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: logURL, to: previous)
            try? "拾光号启动器诊断日志（已轮转）\n".write(to: logURL, atomically: true, encoding: .utf8)
        }
        let date = ISO8601DateFormatter().string(from: Date())
        let line = "[\(date)] \(message.replacingOccurrences(of: "\n", with: " | "))\n"
        guard let data = line.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: logURL) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    }

    // This is a STATIC file-presence check, not an assertion that the game is
    // playable, that each file is valid, or that remote servers are reachable.
    static func checkResources(root: URL?, entry: String) -> (summary: String, details: [String]) {
        guard let root, !entry.isEmpty else {
            return ("未检测到已安装美化包", ["未找到已安装资源目录或 SWF 入口"])
        }
        let manager = FileManager.default
        let folderName = (entry as NSString).deletingLastPathComponent
        let webRoot = folderName.isEmpty ? root : root.appendingPathComponent(folderName, isDirectory: true)
        let webMode = manager.fileExists(atPath: webRoot.appendingPathComponent("index.html").path)
        var lines = ["游戏入口：\(entry)", "安装根目录：\(root.path)",
                     "网页根目录：\(webRoot.path)",
                     "启动模式：\(webMode ? "原始网页 + Ruffle" : "SWF 后备模式")"]
        var missingRequired = 0
        func check(_ title: String, file: URL, required: Bool) {
            let present = manager.fileExists(atPath: file.path)
            lines.append("\(present ? "[OK]" : "[缺失]") \(title)：\(file.lastPathComponent)")
            if required && !present { missingRequired += 1 }
        }
        let resolvedEntry = root.appendingPathComponent(entry)
        check("SWF 入口", file: resolvedEntry, required: true)
        if !manager.fileExists(atPath: resolvedEntry.path) {
            lines.append("[诊断] 预期 SWF 绝对路径：\(resolvedEntry.path)")
            let parent = resolvedEntry.deletingLastPathComponent()
            let siblings = ((try? manager.contentsOfDirectory(atPath: parent.path)) ?? []).prefix(12)
            lines.append("[诊断] SWF 同级目录内容：\(siblings.isEmpty ? "(目录不存在或为空)" : siblings.joined(separator: ", "))")
        }
        if !webMode {
            lines.append("[诊断] index.html 未在 SWF 同级目录出现：\(webRoot.path)")
            // Inspect only the first few matches for a misplaced web root.
            if let scan = manager.enumerator(atPath: root.path) {
                var matches: [String] = []
                while let relative = scan.nextObject() as? String {
                    guard (relative as NSString).lastPathComponent.lowercased() == "index.html" else { continue }
                    let actual = root.appendingPathComponent(relative)
                    if manager.fileExists(atPath: actual.path) { matches.append(relative) }
                    if matches.count == 5 { break }
                }
                lines.append("[诊断] 已安装资源内其他网页入口：\(matches.isEmpty ? "无" : matches.joined(separator: ", "))")
            }
        }
        if webMode {
            check("index.html", file: webRoot.appendingPathComponent("index.html"), required: true)
            check("网页 JS", file: webRoot.appendingPathComponent("assets/index.js"), required: true)
            check("网页 CSS", file: webRoot.appendingPathComponent("assets/index.css"), required: false)
            check("网络 WASM", file: webRoot.appendingPathComponent("assets/nieo_wasm_core_bg.wasm"), required: true)
            check("启动视频（可选）", file: webRoot.appendingPathComponent("video.mp4"), required: false)
        }
        if let ruffle = Bundle.main.url(forResource: "Ruffle", withExtension: nil) {
            check("内置 Ruffle", file: ruffle.appendingPathComponent("ruffle.js"), required: true)
        } else {
            lines.append("[缺失] 内置 Ruffle 文件夹")
            missingRequired += 1
        }
        let summary = missingRequired == 0
          ? "关键文件静态检查通过（不代表游戏已正常加载）"
          : "发现 \(missingRequired) 项关键文件缺失；查看 diagnostics.txt"
        return (summary, lines)
    }
}

enum ImportError: LocalizedError {
    case invalidArchive
    case unsafeEntry(String)
    case noGameFiles
    case invalidPackage
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "文件不是可读取的 ZIP/.srom 压缩包。"
        case .unsafeEntry(let path): return "资源包含不安全路径：\(path)"
        case .noGameFiles: return "资源包内没有找到 SWF。请确认这是完整的游戏资源包。"
        case .invalidPackage: return "找不到已导入的游戏资源。"
        case .unsupportedFormat(let magic): return "文件不是标准 ZIP 压缩格式（文件头：\(magic)）。请提供实际 .srom 文件以确认它的封装格式。"
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var status = "选择导入美化包，将 .srom 游戏资源安装到本机。"
    @Published var isImporting = false
    @Published var localPackages: [URL] = []
    @Published var entries: [String] = []
    @Published var selectedEntry = ""
    @Published var gameRoot: URL?
    @Published var isClearing = false
    @Published var resourceCheckSummary = "尚未检测资源"
    @Published var resourceCheckDetails: [String] = []

    var canStartGame: Bool {
        guard let gameRoot, !selectedEntry.isEmpty else { return false }
        return !isImporting && !isClearing && FileManager.default.fileExists(
            atPath: gameRoot.appendingPathComponent(selectedEntry).path
        )
    }
    var hasInstalledPackage: Bool { gameRoot != nil }

    init() {
        LaunchDiagnostics.prepare()
        LaunchDiagnostics.log("启动器 v4.7 启动；已启用真实相对路径扫描与文件校验；旧资源路径不变")
        let root = Self.savedGameRoot
        if FileManager.default.fileExists(atPath: root.path) {
            gameRoot = root
            entries = Self.findEntries(in: root)
            selectedEntry = Self.preferredEntry(in: entries)
            status = entries.isEmpty ? "已安装资源，但没有找到 SWF 游戏入口。" : "美化包已就绪，可以进入游戏。"
        }
        refreshResourceCheck()
    }

    func refreshResourceCheck() {
        // v1.8 could retain an entry discovered in the temporary extraction
        // directory, even if it was not present at the final installation path.
        if let gameRoot, !selectedEntry.isEmpty,
           !FileManager.default.fileExists(atPath: gameRoot.appendingPathComponent(selectedEntry).path) {
            let verified = Self.findEntries(in: gameRoot)
            entries = verified
            selectedEntry = Self.preferredEntry(in: verified)
            status = verified.isEmpty
                ? "安装目录存在，但未找到可读取的 Client.swf。请查看诊断日志。"
                : "已修正游戏入口路径，请重试进入游戏。"
            LaunchDiagnostics.log("自动重新扫描已安装资源，发现 \(verified.count) 个 SWF 游戏入口")
        }
        let result = LaunchDiagnostics.checkResources(root: gameRoot, entry: selectedEntry)
        resourceCheckSummary = result.summary
        resourceCheckDetails = result.details
        LaunchDiagnostics.log("资源检查：\(result.summary)")
        for item in result.details { LaunchDiagnostics.log("  " + item) }
    }

    // Backup path when a third-party Files provider makes a .srom file gray in
    // the system importer. UIFileSharingEnabled exposes Documents in Files.
    func refreshLocalPackages() {
        LaunchDiagnostics.prepare()
        let documents = LaunchDiagnostics.documents
        let folders = [LaunchDiagnostics.importDirectory,
                       documents, documents.appendingPathComponent("Inbox", isDirectory: true)]
        localPackages = folders.flatMap { folder -> [URL] in
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }
        .filter { url in
            ["srom", "zip"].contains(url.pathExtension.lowercased())
                && ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func importPackage(_ source: URL) {
        guard !isImporting && !isClearing else { return }
        let fileExtension = source.pathExtension.lowercased()
        guard fileExtension == "srom" || fileExtension == "zip" else {
            status = "请选择 .srom 或 .zip 格式的游戏资源包。"
            return
        }
        isImporting = true
        LaunchDiagnostics.log("开始导入美化包：\(source.lastPathComponent)")
        status = "正在复制美化包到应用空间，请勿关闭应用…"
        // Acquire the security-scoped bookmark permission before leaving the
        // file-importer callback; keep access alive until extraction finishes.
        let canAccess = source.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) {
            defer {
                if canAccess { source.stopAccessingSecurityScopedResource() }
            }
            do {
                // First coordinate a copy into our own sandbox. Reading a file
                // provider URL directly for a long unzip is not always reliable.
                let localArchive = try Self.copyIntoSandbox(source)
                defer { try? FileManager.default.removeItem(at: localArchive) }
                await MainActor.run { self.status = "正在校验并解压美化包…较大文件可能需要几分钟" }
                let entries = try Self.extractPackage(localArchive)
                await MainActor.run {
                    self.gameRoot = Self.savedGameRoot
                    self.entries = entries
                    self.selectedEntry = Self.preferredEntry(in: entries)
                    self.status = "美化包已安装，已验证 \(entries.count) 个实际游戏入口。"
                    self.refreshResourceCheck()
                    LaunchDiagnostics.log("资源导入完成：\(entries.count) 个可启动入口")
                    self.isImporting = false
                }
            } catch {
                await MainActor.run {
                    self.status = "导入失败：\(error.localizedDescription)"
                    LaunchDiagnostics.log("资源导入失败：\(error.localizedDescription)")
                    self.isImporting = false
                }
            }
        }
    }


    func clearPackage() {
        guard !isImporting && !isClearing else { return }
        isClearing = true
        LaunchDiagnostics.log("用户请求清除已安装美化包")
        status = "正在清除已安装的美化包…"
        Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let support = Self.savedGameRoot.deletingLastPathComponent()
            let targets = [Self.savedGameRoot, support.appendingPathComponent("Game-backup", isDirectory: true)]
            var failure: Error?
            for url in targets where manager.fileExists(atPath: url.path) {
                do { try manager.removeItem(at: url) }
                catch { failure = error; break }
            }
            await MainActor.run {
                if let failure {
                    self.status = "清除失败：\(failure.localizedDescription)"
                } else {
                    self.gameRoot = nil
                    self.entries = []
                    self.selectedEntry = ""
                    self.status = "已清除美化包，可重新导入 .srom 或 .zip。"
                }
                self.refreshResourceCheck()
                LaunchDiagnostics.log(self.status)
                self.isClearing = false
            }
        }
    }

    private nonisolated static func copyIntoSandbox(_ source: URL) throws -> URL {
        let manager = FileManager.default
        let support = savedGameRoot.deletingLastPathComponent()
        let incoming = support.appendingPathComponent("ImportIncoming", isDirectory: true)
        try manager.createDirectory(at: incoming, withIntermediateDirectories: true)
        let destination = incoming.appendingPathComponent(
            UUID().uuidString + "." + source.pathExtension.lowercased()
        )

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do { try manager.copyItem(at: readableURL, to: destination) }
            catch { copyError = error }
        }
        if let copyError {
            try? manager.removeItem(at: destination)
            throw copyError
        }
        if let coordinationError {
            try? manager.removeItem(at: destination)
            throw coordinationError
        }
        guard manager.fileExists(atPath: destination.path) else {
            throw ImportError.invalidArchive
        }
        return destination
    }

    private nonisolated static var savedGameRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Game", isDirectory: true)
    }

    private nonisolated static func extractPackage(_ source: URL) throws -> [String] {
        let manager = FileManager.default
        // The extension .srom alone does not prove the file is ZIP-based.
        // Read only the signature, not the entire (possibly multi-GB) package.
        let handle = try FileHandle(forReadingFrom: source)
        let signature = try handle.read(upToCount: 8) ?? Data()
        try handle.close()
        let magic = signature.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        let zipMagic = signature.starts(with: [0x50, 0x4B, 0x03, 0x04])
                    || signature.starts(with: [0x50, 0x4B, 0x05, 0x06])
                    || signature.starts(with: [0x50, 0x4B, 0x07, 0x08])
        guard zipMagic else { throw ImportError.unsupportedFormat(magic.isEmpty ? "空文件" : magic) }
        let archive: Archive
        do { archive = try Archive(url: source, accessMode: .read) }
        catch { throw ImportError.invalidArchive }
        for entry in archive {
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            if entry.path.hasPrefix("/")
                || entry.path.contains("\\")
                || components.contains(where: { $0 == ".." || $0 == "." })
                || entry.type == .symlink {
                throw ImportError.unsafeEntry(entry.path)
            }
        }

        let support = savedGameRoot.deletingLastPathComponent()
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        let staging = support.appendingPathComponent("Game-import-\(UUID().uuidString)", isDirectory: true)
        let backup = support.appendingPathComponent("Game-backup", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        try manager.unzipItem(at: source, to: staging, skipCRC32: false)
        let entries = findEntries(in: staging)
        guard !entries.isEmpty else { throw ImportError.noGameFiles }
        LaunchDiagnostics.log("临时解压目录已验证：\(entries.joined(separator: ", "))")

        if manager.fileExists(atPath: backup.path) {
            try manager.removeItem(at: backup)
        }
        let existing = manager.fileExists(atPath: savedGameRoot.path)
        if existing { try manager.moveItem(at: savedGameRoot, to: backup) }
        do {
            try manager.moveItem(at: staging, to: savedGameRoot)
        } catch {
            if existing { try? manager.moveItem(at: backup, to: savedGameRoot) }
            throw error
        }
        // The staging folder has moved. Re-enumerate the actual installed path
        // rather than assuming every staging relative path still resolves.
        // This also catches a partial package or an unexpected ZIP wrapper.
        let installedEntries = findEntries(in: savedGameRoot)
        guard !installedEntries.isEmpty else {
            // Never leave a broken installation in place after replacing an old one.
            try? manager.removeItem(at: savedGameRoot)
            if existing && manager.fileExists(atPath: backup.path) {
                try? manager.moveItem(at: backup, to: savedGameRoot)
            }
            throw ImportError.noGameFiles
        }
        for relative in installedEntries {
            let actual = savedGameRoot.appendingPathComponent(relative)
            guard manager.fileExists(atPath: actual.path) else {
                throw ImportError.invalidPackage
            }
        }
        LaunchDiagnostics.log("安装后路径校验完成：\(installedEntries.joined(separator: ", "))")
        if existing { try? manager.removeItem(at: backup) }
        return installedEntries
    }

    // FileManager.enumerator(atPath:) returns paths RELATIVE to `root.path`.
    // The URL-based enumerator's `url.path` is not guaranteed to have the same
    // textual prefix as the input root URL (e.g. /var vs /private/var), so
    // `dropFirst(root.path.count + 1)` can yield a truncated, nonexistent path.
    private nonisolated static func findEntries(in root: URL) -> [String] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = manager.enumerator(atPath: root.path) else { return [] }

        var found: [String] = []
        while let relative = enumerator.nextObject() as? String {
            guard (relative as NSString).pathExtension.lowercased() == "swf" else { continue }
            // Validate the actual target before exposing a launch entry.
            let file = root.appendingPathComponent(relative)
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  manager.isReadableFile(atPath: file.path) else { continue }
            found.append(relative)
        }

        let candidates = found.filter { path in
            ["client.swf", "main.swf", "game.swf"].contains(path.lastPathComponent.lowercased())
        }
        let launchable = candidates.isEmpty
            ? found.filter { $0.split(separator: "/").count <= 2 }
            : candidates
        return launchable.sorted { a, b in
            let folderA = (a as NSString).deletingLastPathComponent
            let folderB = (b as NSString).deletingLastPathComponent
            let webA = manager.fileExists(atPath: root.appendingPathComponent(folderA).appendingPathComponent("index.html").path)
            let webB = manager.fileExists(atPath: root.appendingPathComponent(folderB).appendingPathComponent("index.html").path)
            if webA != webB { return webA }
            let depthA = a.split(separator: "/").count
            let depthB = b.split(separator: "/").count
            if depthA != depthB { return depthA < depthB }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    private nonisolated static func preferredEntry(in entries: [String]) -> String {
        for name in ["Client.swf", "Main.swf", "Game.swf"] {
            if let match = entries.first(where: { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }) {
                return match
            }
        }
        return entries.first ?? ""
    }
}

private extension String {
    var lastPathComponent: String { (self as NSString).lastPathComponent }
}
