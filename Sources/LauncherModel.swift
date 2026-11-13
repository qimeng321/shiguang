import Foundation
import CryptoKit
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

                Import/：可放入 .srom、完整 .zip 美化包或游戏增量 .zip，在启动器的“导入美化包”里选择从共享文件夹导入。
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

    // A completed unzip already checks CRC32. For launch/upgrade checks, examine
    // the critical game files and their headers, not merely the SWF filename.
    // This is a bounded disk check (11 small headers/metadata) even for 3GB packs.
    static let receiptName = ".shiguang-install-verified"
    static func normalizedResourcePath(_ rawValue: String, relativeDirectory: String = "") -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let query = value.firstIndex(of: "?") { value = String(value[..<query]) }
        if let fragment = value.firstIndex(of: "#") { value = String(value[..<fragment]) }
        value = value.replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("/") { value.removeFirst() }
        if value.hasPrefix("./") {
            value = String(value.dropFirst(2))
            if !relativeDirectory.isEmpty { value = relativeDirectory + "/" + value }
        } else if !value.contains("/"), !relativeDirectory.isEmpty {
            value = relativeDirectory + "/" + value
        }
        let parts = value.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { return nil }
        return parts.joined(separator: "/")
    }

    // Read the exact core SWF path declared by the package's dll.xml.
    // The 0.18.0 package declares <item path="dll/SGCore.swf?revision"...>.
    static func configuredCorePath(base: URL) -> String? {
        let fm = FileManager.default
        let config = base.appendingPathComponent("config/dll.xml")
        guard let values = try? config.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 128 * 1024,
              let xml = try? String(contentsOf: config, encoding: .utf8),
              let regex = try? NSRegularExpression(
                pattern: #"(?i)<item\b[^>]*\bpath\s*=\s*["']([^"']+\.swf(?:\?[^"']*)?)["']"#),
              let range = Range(NSRange(xml.startIndex..., in: xml), in: xml) else {
            for candidate in ["dll/NieoCore.swf", "dll/SGCore.swf"] {
                if fm.fileExists(atPath: base.appendingPathComponent(candidate).path) { return candidate }
            }
            return nil
        }
        for match in regex.matches(in: xml, range: NSRange(range, in: xml)) {
            guard match.numberOfRanges > 1,
                  let pathRange = Range(match.range(at: 1), in: xml),
                  let relative = normalizedResourcePath(String(xml[pathRange])),
                  relative.lowercased().hasSuffix(".swf") else { continue }
            return relative
        }
        for candidate in ["dll/NieoCore.swf", "dll/SGCore.swf"] {
            if fm.fileExists(atPath: base.appendingPathComponent(candidate).path) { return candidate }
        }
        return nil
    }

    // Resolve the WASM file actually named in assets/index.js. Its wasm-bindgen
    // glue can be bundled in index.js; no separate nieo_wasm_core_bg.js is needed.
    static func configuredWASMPath(base: URL) -> String? {
        let fm = FileManager.default
        let js = base.appendingPathComponent("assets/index.js")
        if let values = try? js.resourceValues(forKeys: [.fileSizeKey]),
           (values.fileSize ?? 0) <= 64 * 1024 * 1024,
           let source = try? String(contentsOf: js, encoding: .utf8),
           let regex = try? NSRegularExpression(
                pattern: #"["']([^"']+\.wasm(?:\?[^"']*)?)["']"#,
                options: [.caseInsensitive]),
           let range = Range(NSRange(source.startIndex..., in: source), in: source) {
            for match in regex.matches(in: source, range: NSRange(range, in: source)) {
                guard match.numberOfRanges > 1,
                      let pathRange = Range(match.range(at: 1), in: source),
                      let relative = normalizedResourcePath(
                        String(source[pathRange]), relativeDirectory: "assets"),
                      relative.lowercased().hasSuffix(".wasm") else { continue }
                return relative
            }
        }
        for candidate in ["assets/nieo_wasm_core_bg.wasm", "assets/SG_wasm_core_bg.wasm"] {
            if fm.fileExists(atPath: base.appendingPathComponent(candidate).path) { return candidate }
        }
        return nil
    }

    static func validateInstalledPackage(root: URL, entry: String) -> [String] {
        let fm = FileManager.default
        guard !entry.isEmpty else { return ["没有找到可启动的游戏 SWF 入口"] }
        let folder = (entry as NSString).deletingLastPathComponent
        let base = folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
        var failures: [String] = []
        func require(_ relative: String, minimum: UInt64 = 1,
                     magic: [UInt8]? = nil) {
            let file = base.appendingPathComponent(relative)
            guard let values = try? file.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ]), values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  UInt64(max(0, values.fileSize ?? 0)) >= minimum,
                  fm.isReadableFile(atPath: file.path) else {
                failures.append("\(relative)：缺失、不可读或大小异常")
                return
            }
            if let magic {
                do {
                    let handle = try FileHandle(forReadingFrom: file)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: magic.count) ?? Data()
                    if Array(data) != magic { failures.append("\(relative)：文件头无效") }
                } catch {
                    failures.append("\(relative)：无法读取文件头")
                }
            }
        }

        // SWF must have a valid FWS/CWS/ZWS signature; reject empty/damaged stubs.
        let swf = root.appendingPathComponent(entry)
        if let attributes = try? fm.attributesOfItem(atPath: swf.path),
           let count = (attributes[.size] as? NSNumber)?.uint64Value,
           count >= 64, fm.isReadableFile(atPath: swf.path),
           let handle = try? FileHandle(forReadingFrom: swf) {
            let prefix = (try? handle.read(upToCount: 3)) ?? Data()
            try? handle.close()
            if !["FWS", "CWS", "ZWS"].contains(String(data: prefix, encoding: .ascii) ?? "") {
                failures.append("游戏入口 \(entry)：SWF 文件头无效")
            }
        } else {
            failures.append("游戏入口 \(entry)：文件缺失或内容过短")
        }

        // Web packages are validated against their own JS/WASM and dll.xml paths.
        // Stand-alone SWF packages keep the legacy fallback behavior.
        if fm.fileExists(atPath: base.appendingPathComponent("index.html").path) || !folder.isEmpty {
            require("index.html", minimum: 64)
            require("assets/index.js", minimum: 64)
            if let wasmPath = configuredWASMPath(base: base) {
                require(wasmPath, minimum: 8, magic: [0x00, 0x61, 0x73, 0x6D])
            } else {
                failures.append("assets/index.js：未识别到实际引用的 WASM 文件，且未找到兼容路径")
            }
            require("config/doorConfig.xml", minimum: 8)
            require("config/ServerR.xml", minimum: 8)
            require("config/dll.xml", minimum: 8)
            require("version.swf", minimum: 6)
            require("resource/main_resource.swf", minimum: 64)
            require("resource/map/1.swf", minimum: 64)
            require("resource/ui.swf", minimum: 64)
            if let corePath = configuredCorePath(base: base) {
                require(corePath, minimum: 64)
            } else {
                failures.append("config/dll.xml：未识别到游戏核心 SWF 路径，且未找到 NieoCore/SGCore")
            }
            require("login/Login.swf", minimum: 64)
        }
        return failures
    }

    // Read the revision of the official core bundle without interpreting or
    // changing arbitrary SWF content. This can label supported .srom packs.
    static func coreRevision(root: URL, entry: String) -> String? {
        guard !entry.isEmpty else { return nil }
        let folder = (entry as NSString).deletingLastPathComponent
        let base = folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
        let config = base.appendingPathComponent("config/dll.xml")
        guard let values = try? config.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 128 * 1024,
              let text = try? String(contentsOf: config, encoding: .utf8),
              let item = text.components(separatedBy: "ver=\"").dropFirst().first else {
            return nil
        }
        let revision = String(item.prefix(while: { $0.isNumber }))
        return (revision.count >= 6 && revision.count <= 12) ? revision : nil
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
        // This is a non-blocking fingerprint label, not a hard-coded version lock.
        if let bytes = try? Data(contentsOf: resolvedEntry, options: .mappedIfSafe),
           bytes.count <= 2_000_000 {
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            if digest == "d64a9e3af813324f6e1f9844e74eee16dee5d76a4c8a26c417585467a3c3e59f" {
                lines.append("[新版资源] Client.swf 与 0.18.0 分析样本匹配，原 PVM 兼容补丁适用")
            } else {
                lines.append("[资源识别] 未知 Client.swf 指纹，由启动流程自行验证 PVM 补丁")
            }
        }
        if let revision = coreRevision(root: root, entry: entry) {
            lines.append("[核心资源修订] " + revision +
                (revision == "2026110304" ? "（已知 0.18.0 版本）" : "（尚未单独验证）"))
        }
        let versionFile = webRoot.appendingPathComponent("base.version")
        if let text = try? String(contentsOf: versionFile, encoding: .utf8),
           text.count <= 40 {
            lines.append("[资源版本] " + text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
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
            if let wasmPath = configuredWASMPath(base: webRoot) {
                check("网络 WASM（index.js 引用）", file: webRoot.appendingPathComponent(wasmPath), required: true)
            } else {
                lines.append("[缺失] assets/index.js：未识别到 WASM 路径")
                missingRequired += 1
            }
            if let corePath = configuredCorePath(base: webRoot) {
                check("游戏核心（dll.xml）", file: webRoot.appendingPathComponent(corePath), required: true)
            } else {
                lines.append("[缺失] config/dll.xml：未识别到游戏核心路径")
                missingRequired += 1
            }
            check("启动视频（可选）", file: webRoot.appendingPathComponent("video.mp4"), required: false)
        }
        if let ruffle = Bundle.main.url(forResource: "Ruffle", withExtension: nil) {
            check("内置 Ruffle", file: ruffle.appendingPathComponent("ruffle.js"), required: true)
        } else {
            lines.append("[缺失] 内置 Ruffle 文件夹")
            missingRequired += 1
        }
        let issues = validateInstalledPackage(root: root, entry: entry)
        for issue in issues.prefix(12) { lines.append("[校验失败] " + issue) }
        let summary = (missingRequired == 0 && issues.isEmpty)
          ? "关键文件校验通过（不代表完整资源或游戏联网已正常）"
          : "资源校验未通过：\(missingRequired) 项关键文件缺失、\(issues.count) 项内容异常；请重新导入"
        return (summary, lines)
    }
}

enum ImportError: LocalizedError {
    case invalidArchive
    case unsafeEntry(String)
    case noGameFiles
    case invalidPackage
    case invalidContents(String)
    case referenceOnlyPackage
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "文件不是可读取的 ZIP/.srom 压缩包。"
        case .unsafeEntry(let path): return "资源包含不安全路径：\(path)"
        case .noGameFiles: return "资源包内没有找到 SWF。请确认这是完整的游戏资源包。"
        case .invalidPackage: return "找不到已导入的游戏资源。"
        case .invalidContents(let details): return "美化包关键文件不完整或异常：\(details)"
        case .referenceOnlyPackage: return "这是开发用资源解析参考包（只含核心文件），不是完整游戏美化包。请导入原始完整 .srom，不能用本参考 ZIP 替代。"
        case .unsupportedFormat(let magic): return "文件不是标准 ZIP 压缩格式（文件头：\(magic)）。请提供实际 .srom 文件以确认它的封装格式。"
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var status = "选择导入美化包，将 .srom 游戏资源安装到本机。"
    @Published var isImporting = false
    @Published private(set) var importProgress: Double = 0
    @Published private(set) var importPhase = ""
    // The copy/unzip bar measures byte progress only. Once unzip ends, show
    // indeterminate installation stages instead of leaving a misleading 93%.
    @Published private(set) var isImportFinishing = false
    private var importStageRank = 0
    @Published var localPackages: [URL] = []
    @Published var entries: [String] = []
    @Published var selectedEntry = ""
    @Published var gameRoot: URL?
    @Published var isClearing = false
    @Published var resourceCheckSummary = "尚未检测资源"
    @Published var resourceCheckDetails: [String] = []
    @Published private(set) var resourceRevision: String?
    @Published private(set) var isInstalledValidated = false
    @Published private(set) var lastImportFailed = false
    @Published var importFailureMessage: String?
    @Published private(set) var patchSummary = MobilePatchManager.activeSummary
    @Published private(set) var patchBusy = false
    @Published var patchError: String?
    @Published private(set) var patchStatus = "可导入或撤销手机适配补丁，不修改原美化包。"

    // Completely independent from full .srom and mobile .sgpatch imports.
    @Published private(set) var deltaBusy = false
    @Published private(set) var deltaProgress: Double = 0
    @Published private(set) var deltaPhase = ""
    @Published private(set) var deltaStatus = "仅合并变化的资源；自动检查版本、备份与回滚。"
    @Published private(set) var deltaPreview: GameIncrementalPreview?
    @Published var deltaError: String?
    @Published private(set) var deltaRecoveryProblem: String?
    private var deltaPendingArchive: URL?

    var canStartGame: Bool {
        guard let gameRoot, !selectedEntry.isEmpty, isInstalledValidated else { return false }
        return !isImporting && !isClearing && !deltaBusy && deltaRecoveryProblem == nil && FileManager.default.fileExists(
            atPath: gameRoot.appendingPathComponent(selectedEntry).path
        )
    }
    var hasInstalledPackage: Bool { gameRoot != nil }

    private func reportImportProgress(_ value: Double, phase: String) {
        guard isImporting, !isImportFinishing, value.isFinite else { return }
        let normalized = min(1, max(0, value))
        // Multiple background tasks may report completion out of order.
        // Never let the visible bar go backward during an active import.
        if normalized + 0.00001 >= importProgress {
            importProgress = max(importProgress, normalized)
            if importPhase != phase { importPhase = phase }
        }
    }

    private func reportImportFinalizing(_ rank: Int, phase: String) {
        guard isImporting, rank > importStageRank else { return }
        importStageRank = rank
        isImportFinishing = true
        importPhase = phase
        status = "解压及 CRC 校验已完成，正在完成安装与最终核验，请勿关闭应用…"
        LaunchDiagnostics.log("[资源导入收尾] 阶段\(rank)：\(phase)")
    }

    init() {
        LaunchDiagnostics.prepare()
        LaunchDiagnostics.log("启动器 正式版 1.08（Build 130 · 通用手机补丁）启动；保留 1.07 原功能")
        do {
            try GameIncrementalUpdater.recoverIfNeeded(gameRoot: Self.savedGameRoot)
        } catch {
            deltaRecoveryProblem = error.localizedDescription
            deltaError = "上次增量更新未完全恢复：\(error.localizedDescription)"
            LaunchDiagnostics.log("[增量更新] 启动恢复失败，已阻止进入游戏：\(error.localizedDescription)")
        }
        let root = Self.savedGameRoot
        if FileManager.default.fileExists(atPath: root.path) {
            gameRoot = root
            entries = Self.findEntries(in: root)
            selectedEntry = Self.preferredEntry(in: entries)
            status = "正在核对上次安装的资源…"
        }
        refreshResourceCheck()
        if isInstalledValidated {
            let hasReceipt = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(LaunchDiagnostics.receiptName).path
            )
            status = hasReceipt
                ? "已验证上次完整导入，关键资源正常，可进入游戏。"
                : "旧版已安装资源通过关键文件校验，可进入游戏；重新导入可完成完整 CRC 校验。"
        } else if gameRoot != nil {
            status = "检测到不完整的旧美化包，请清除并重新导入。"
        }
    }

    func refreshResourceCheck() {
        // Failed extraction may have removed the unusable private Game directory.
        // Do not keep a stale gameRoot pointer that makes "清除美化包" look enabled.
        if let root = gameRoot, !FileManager.default.fileExists(atPath: root.path) {
            gameRoot = nil
            entries = []
            selectedEntry = ""
            isInstalledValidated = false
        }
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
        if let gameRoot {
            isInstalledValidated = LaunchDiagnostics.validateInstalledPackage(
                root: gameRoot, entry: selectedEntry
            ).isEmpty
            resourceRevision = LaunchDiagnostics.coreRevision(
                root: gameRoot, entry: selectedEntry
            )
        } else {
            isInstalledValidated = false
            resourceRevision = nil
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
        guard !isImporting && !isClearing && !deltaBusy else { return }
        let fileExtension = source.pathExtension.lowercased()
        guard fileExtension == "srom" || fileExtension == "zip" else {
            lastImportFailed = true
            status = "导入失败：文件格式不支持。"
            importFailureMessage = "请选择 .srom 或 .zip 格式的游戏资源包。"
            return
        }
        lastImportFailed = false
        importFailureMessage = nil
        isImporting = true
        isImportFinishing = false
        importStageRank = 0
        importProgress = 0
        importPhase = "复制资源包"
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
                let localArchive = try Self.copyIntoSandbox(source) { fraction in
                    Task { @MainActor in
                        self.reportImportProgress(0.20 * fraction, phase: "正在复制资源包")
                    }
                }
                defer { try? FileManager.default.removeItem(at: localArchive) }
                await MainActor.run {
                    self.reportImportProgress(0.20, phase: "正在检查压缩包")
                    self.status = "正在解压美化包并校验文件完整性…"
                }
                let unzipProgress = Progress(totalUnitCount: 0)
                // ZIPFoundation supplies real completed/total byte counts as each
                // archive entry is decompressed. Poll on a non-main task.
                let monitor = Task.detached(priority: .utility) {
                    while !Task.isCancelled {
                        let fraction = unzipProgress.totalUnitCount > 0
                            ? min(1.0, max(0.0, unzipProgress.fractionCompleted))
                            : 0.0
                        await MainActor.run {
                            self.reportImportProgress(0.20 + fraction * 0.73,
                                                      phase: "正在解压并校验")
                        }
                        try? await Task.sleep(nanoseconds: 180_000_000)
                    }
                }
                let entries: [String]
                do {
                    entries = try Self.extractPackage(
                        localArchive, progress: unzipProgress,
                        onFinalizing: { rank, phase in
                            Task { @MainActor in
                                self.reportImportFinalizing(rank, phase: phase)
                            }
                        }
                    )
                } catch {
                    monitor.cancel()
                    await monitor.value
                    throw error
                }
                monitor.cancel()
                await monitor.value
                await MainActor.run {
                    self.reportImportFinalizing(7, phase: "正在刷新安装状态")
                    self.gameRoot = Self.savedGameRoot
                    self.entries = entries
                    self.selectedEntry = Self.preferredEntry(in: entries)
                    self.status = "美化包已安装，已验证 \(entries.count) 个实际游戏入口。"
                    self.refreshResourceCheck()
                    guard self.isInstalledValidated else {
                        // A failed content check must never result in a green
                        // ready label even when a Client.swf filename exists.
                        self.status = "安装后的资源校验失败，请重新导入。"
                        self.importPhase = "资源校验失败"
                        self.lastImportFailed = true
                        self.importFailureMessage = "美化包文件缺失或内容异常。请重新选择原始文件导入。"
                        LaunchDiagnostics.log("[资源校验失败] " + self.resourceCheckSummary)
                        self.isImporting = false
                        return
                    }
                    LaunchDiagnostics.log("资源导入完成：\(entries.count) 个可启动入口")
                    self.isImportFinishing = false
                    self.importProgress = 1.0
                    self.importPhase = "安装完成"
                    self.isImporting = false
                }
            } catch {
                // Remove only failed incoming copies and incomplete staging.
                // An older VALID Game installation must never be erased by a
                // broken replacement archive.
                let cleanup = Self.cleanupFailedImport()
                await MainActor.run {
                    self.refreshResourceCheck()
                    self.lastImportFailed = true
                    self.status = self.isInstalledValidated
                        ? "本次导入失败，原有完好资源已保留。"
                        : "导入失败；临时及无效资源已清理，请重新导入。"
                    self.isImportFinishing = false
                    self.importPhase = "导入失败"
                    self.importFailureMessage = "导入失败：\(error.localizedDescription)\n\n\(cleanup)\n请选择美化包重新导入。"
                    LaunchDiagnostics.log("资源导入失败：\(error.localizedDescription)；清理：\(cleanup)")
                    self.isImporting = false
                    self.importProgress = 0
                }
            }
        }
    }


    // Step 1: preview a ZIP-structured .zip/.srom game delta; do not modify Game.
    func prepareIncrementalUpdate(_ source: URL) {
        guard !deltaBusy && !isImporting && !isClearing && !patchBusy else { return }
        guard isInstalledValidated, let root = gameRoot, deltaRecoveryProblem == nil else {
            deltaError = "请先安装并校验完整资源包，或解决未完成更新的回滚问题。"
            return
        }
        guard ["zip", "srom"].contains(source.pathExtension.lowercased()) else {
            deltaError = "请选择 .zip 或 .srom 游戏增量包；手机适配补丁请使用下方独立入口。"
            return
        }
        cancelPreparedIncrementalUpdate()
        deltaBusy = true
        deltaProgress = 0
        deltaPhase = "正在复制并检查增量包"
        deltaStatus = "正在预检版本、路径及文件大小，不会修改现有资源。"
        let entry = selectedEntry
        let scoped = source.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) {
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            var local: URL?
            do {
                let copied = try Self.copyIntoSandbox(source) { fraction in
                    Task { @MainActor in
                        self.deltaProgress = max(self.deltaProgress, fraction * 0.3)
                    }
                }
                local = copied
                let preview = try GameIncrementalUpdater.inspect(
                    archiveURL: copied, gameRoot: root, entry: entry)
                await MainActor.run {
                    self.deltaPendingArchive = copied
                    self.deltaPreview = preview
                    self.deltaBusy = false
                    self.deltaProgress = 0
                    self.deltaStatus = "预检通过：\(preview.currentRevision) → \(preview.targetRevision)，\(preview.fileCount) 个文件。请确认更新。"
                    LaunchDiagnostics.log("[增量更新] 预检通过，目标=\(preview.targetRevision)，\(preview.fileCount) 文件、覆盖 \(preview.overwriteCount)、新增 \(preview.addedCount)")
                }
            } catch {
                if let local { try? FileManager.default.removeItem(at: local) }
                await MainActor.run {
                    self.deltaBusy = false
                    self.deltaProgress = 0
                    self.deltaPhase = "预检失败"
                    self.deltaStatus = "增量更新没有开始，已安装的游戏资源未改变。"
                    self.deltaError = error.localizedDescription
                    LaunchDiagnostics.log("[增量更新] 预检拒绝：\(error.localizedDescription)")
                }
            }
        }
    }

    func cancelPreparedIncrementalUpdate() {
        if let pending = deltaPendingArchive { try? FileManager.default.removeItem(at: pending) }
        deltaPendingArchive = nil
        deltaPreview = nil
    }

    // Step 2: merge only after confirmation; the transaction owns rollback.
    func installPreparedIncrementalUpdate() {
        guard !deltaBusy && !isImporting && !isClearing && !patchBusy,
              let archive = deltaPendingArchive, deltaPreview != nil,
              let root = gameRoot, deltaRecoveryProblem == nil else { return }
        let entry = selectedEntry
        deltaPendingArchive = nil
        deltaPreview = nil
        deltaBusy = true
        deltaProgress = 0.02
        deltaPhase = "正在进行安全增量更新"
        deltaStatus = "正在备份并合并变动资源，请勿关闭应用。"
        Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: archive) }
            do {
                let result = try GameIncrementalUpdater.install(
                    archiveURL: archive, gameRoot: root, entry: entry,
                    onProgress: { fraction, phase in
                        Task { @MainActor in
                            self.deltaProgress = max(self.deltaProgress, fraction)
                            self.deltaPhase = phase
                        }
                    })
                await MainActor.run {
                    self.refreshResourceCheck()
                    self.patchSummary = MobilePatchManager.activeSummary
                    self.deltaBusy = false
                    self.deltaProgress = 1.0
                    self.deltaPhase = "增量更新成功"
                    self.deltaStatus = "更新成功：\(result.currentRevision) → \(result.targetRevision)，合并 \(result.fileCount) 个资源；重新进入游戏生效。"
                }
            } catch {
                await MainActor.run {
                    self.refreshResourceCheck()
                    self.deltaBusy = false
                    self.deltaProgress = 0
                    self.deltaPhase = "更新失败"
                    self.deltaStatus = "安装中止；原资源将保留或按日志回滚。"
                    self.deltaError = error.localizedDescription
                    if case GameIncrementalError.rollbackFailed = error {
                        self.deltaRecoveryProblem = error.localizedDescription
                    }
                    LaunchDiagnostics.log("[增量更新] 安装失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func importMobilePatch(_ url: URL) {
        guard !patchBusy && !isImporting && !isClearing && !deltaBusy else { return }
        guard isInstalledValidated, let installedGameRoot = gameRoot else {
            patchError = "请先导入并验证完整的 .srom 游戏资源，再安装手机补丁。"
            return
        }
        patchBusy = true
        patchStatus = "正在检查补丁清单并校验 ZIP CRC32…"
        patchError = nil
        let revision = resourceRevision
        let scoped = url.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let result = try MobilePatchManager.install(url, currentRevision: revision, gameRoot: installedGameRoot)
                await MainActor.run {
                    self.patchSummary = result
                    self.patchStatus = "补丁已启用；退出并重新进入游戏后生效。"
                    self.patchBusy = false
                }
            } catch {
                LaunchDiagnostics.log("[手机补丁] 导入失败：\(error.localizedDescription)")
                await MainActor.run {
                    self.patchSummary = MobilePatchManager.activeSummary
                    self.patchStatus = "补丁安装未完成，原游戏资源与原补丁保持不变。"
                    self.patchError = error.localizedDescription
                    self.patchBusy = false
                }
            }
        }
    }

    func clearMobilePatch() {
        guard !patchBusy && !isImporting && !isClearing && !deltaBusy else { return }
        patchBusy = true
        patchStatus = "正在撤销补丁…"
        Task.detached(priority: .userInitiated) {
            do {
                try MobilePatchManager.clear()
                await MainActor.run {
                    self.patchSummary = MobilePatchManager.activeSummary
                    self.patchStatus = "补丁已撤销；重新进入游戏将使用原始资源。"
                    self.patchBusy = false
                }
            } catch {
                await MainActor.run {
                    self.patchError = "清除补丁失败：\(error.localizedDescription)"
                    self.patchBusy = false
                }
            }
        }
    }

    func clearPackage() {
        guard !isImporting && !isClearing && !deltaBusy else { return }
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
                    self.isInstalledValidated = false
                    self.lastImportFailed = false
                    self.status = "已清除美化包，可重新导入 .srom 或 .zip。"
                }
                self.refreshResourceCheck()
                LaunchDiagnostics.log(self.status)
                self.isClearing = false
            }
        }
    }

    private nonisolated static func cleanupFailedImport() -> String {
        let fm = FileManager.default
        let support = savedGameRoot.deletingLastPathComponent()
        var removed = 0
        // No user-owned Downloads / Documents / Import files are touched.
        let incoming = support.appendingPathComponent("ImportIncoming", isDirectory: true)
        if fm.fileExists(atPath: incoming.path) {
            if (try? fm.removeItem(at: incoming)) != nil { removed += 1 }
        }
        if let files = try? fm.contentsOfDirectory(at: support,
                                                  includingPropertiesForKeys: nil) {
            for url in files where url.lastPathComponent.hasPrefix("Game-import-") {
                if (try? fm.removeItem(at: url)) != nil { removed += 1 }
            }
        }
        let root = savedGameRoot
        if fm.fileExists(atPath: root.path) {
            let selected = preferredEntry(in: findEntries(in: root))
            if !LaunchDiagnostics.validateInstalledPackage(root: root, entry: selected).isEmpty {
                if (try? fm.removeItem(at: root)) != nil { removed += 1 }
            }
        }
        return "已清理 \(removed) 处失败导入残留；“文件”App 中的原始资源包未删除。"
    }

    private nonisolated static func copyIntoSandbox(
        _ source: URL, onProgress: (Double) -> Void
    ) throws -> URL {
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
            do {
                // Stream the file in 1 MiB chunks to avoid reading a multi-GB
                // .srom into memory and to expose REAL bytes copied.
                guard manager.createFile(atPath: destination.path, contents: nil) else {
                    throw ImportError.invalidArchive
                }
                let reader = try FileHandle(forReadingFrom: readableURL)
                defer { try? reader.close() }
                let writer = try FileHandle(forWritingTo: destination)
                defer { try? writer.close() }
                let attributes = try manager.attributesOfItem(atPath: readableURL.path)
                let totalBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                var copied: Int64 = 0
                var lastPercent = -1
                while let chunk = try reader.read(upToCount: 1_048_576), !chunk.isEmpty {
                    try writer.write(contentsOf: chunk)
                    copied += Int64(chunk.count)
                    if totalBytes > 0 {
                        let fraction = min(1.0, Double(copied) / Double(totalBytes))
                        let percent = Int(fraction * 100)
                        if percent != lastPercent {
                            lastPercent = percent
                            onProgress(fraction)
                        }
                    }
                }
                onProgress(1.0)
            } catch { copyError = error }
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

    private nonisolated static func extractPackage(
        _ source: URL, progress: Progress,
        onFinalizing: @escaping @Sendable (Int, String) -> Void
    ) throws -> [String] {
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
        var containsReferenceManifest = false
        var containsPlayableMap = false
        for entry in archive {
            if entry.path == "manifest.json" { containsReferenceManifest = true }
            if entry.path.hasSuffix("/resource/map/1.swf") {
                containsPlayableMap = true
            }
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            if entry.path.hasPrefix("/")
                || entry.path.contains("\\")
                || components.contains(where: { $0 == ".." || $0 == "." })
                || entry.type == .symlink {
                throw ImportError.unsafeEntry(entry.path)
            }
        }
        // Reject the small reference-only ZIP before expanding/replacing any
        // installed multi-GB game package. Existing installation stays intact.
        if containsReferenceManifest && !containsPlayableMap {
            throw ImportError.referenceOnlyPackage
        }

        let support = savedGameRoot.deletingLastPathComponent()
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        let staging = support.appendingPathComponent("Game-import-\(UUID().uuidString)", isDirectory: true)
        let backup = support.appendingPathComponent("Game-backup", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        try manager.unzipItem(at: source, to: staging, skipCRC32: false, progress: progress)
        onFinalizing(1, "解压 100% · 正在扫描游戏入口")
        let entries = findEntries(in: staging)
        guard !entries.isEmpty else { throw ImportError.noGameFiles }
        let chosenEntry = preferredEntry(in: entries)
        onFinalizing(2, "正在校验地图、配置和核心文件")
        let issues = LaunchDiagnostics.validateInstalledPackage(root: staging, entry: chosenEntry)
        guard issues.isEmpty else {
            throw ImportError.invalidContents(issues.prefix(3).joined(separator: "；"))
        }
        LaunchDiagnostics.log("临时解压目录已验证：\(entries.joined(separator: ", "))")
        // Only a complete CRC32-verified import with all critical files may
        // carry the ready receipt into the actual installed Game directory.
        let receipt = staging.appendingPathComponent(LaunchDiagnostics.receiptName)
        try "full-unzip-crc32-ok; key-files-valid; v1.04\n".write(
            to: receipt, atomically: true, encoding: .utf8)

        onFinalizing(3, "正在准备安全安装及旧版备份")
        if manager.fileExists(atPath: backup.path) {
            try manager.removeItem(at: backup)
        }
        let existing = manager.fileExists(atPath: savedGameRoot.path)
        if existing { try manager.moveItem(at: savedGameRoot, to: backup) }
        onFinalizing(4, "正在安装新资源包（保留原版备份）")
        do {
            try manager.moveItem(at: staging, to: savedGameRoot)
        } catch {
            if existing { try? manager.moveItem(at: backup, to: savedGameRoot) }
            throw error
        }
        // Avoid re-enumerating tens of thousands of files after an atomic
        // directory move. Verify the SAME discovered entry paths at destination
        // and re-check critical file headers; restore the old installation if
        // the new destination has unexpectedly become incomplete.
        onFinalizing(5, "正在核验已安装的游戏文件")
        let installedEntries = entries
        for relative in installedEntries {
            let actual = savedGameRoot.appendingPathComponent(relative)
            guard manager.fileExists(atPath: actual.path) else {
                try? manager.removeItem(at: savedGameRoot)
                if existing { try? manager.moveItem(at: backup, to: savedGameRoot) }
                throw ImportError.invalidPackage
            }
        }
        let postIssues = LaunchDiagnostics.validateInstalledPackage(
            root: savedGameRoot, entry: chosenEntry
        )
        guard postIssues.isEmpty else {
            try? manager.removeItem(at: savedGameRoot)
            if existing { try? manager.moveItem(at: backup, to: savedGameRoot) }
            throw ImportError.invalidContents(postIssues.prefix(3).joined(separator: "；"))
        }
        LaunchDiagnostics.log("安装后路径校验完成：\(installedEntries.joined(separator: ", "))")
        onFinalizing(6, "正在清理旧版备份并完成安装")
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


// TEST 1.2 BUILD 115. Mobile patches form a read-only HTTP shadow tree.
// The original multi-gigabyte Application Support/Game tree is NEVER
// overwritten, copied, extracted again, or deleted by patch operations.
struct MobilePatchManifest: Codable {
    let format: String
    let name: String
    let version: String
    let targetRevision: String?
    let files: [String]
    // Optional for legacy resource-only patches. Mandatory for dll/SGCore.swf.
    let originalSHA256: [String: String]?
}

enum MobilePatchError: LocalizedError {
    case invalidFormat, invalidManifest, invalidArchive, incompatible(String)
    case unsafePath(String), invalidFile(String), oversized, noAssets, coreMismatch(String)
    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "补丁文件必须是 ZIP 格式（扩展名 .sgpatch 或 .zip）。"
        case .invalidManifest: return "缺少有效的 mobile-patch.json，或文件清单与 ZIP 内容不一致。"
        case .invalidArchive: return "补丁压缩包无法读取或校验失败。"
        case .incompatible(let version): return "此补丁仅适用于核心资源修订号 \(version)，与当前美化包不匹配。"
        case .unsafePath(let path): return "补丁包含不安全或不支持的资源路径：\(String(path.prefix(120)))"
        case .invalidFile(let path): return "补丁资源缺失或不是普通文件：\(path)"
        case .oversized: return "补丁过大：单包最多 512 MB、2048 个资源文件。"
        case .noAssets: return "补丁清单没有可覆盖的游戏资源。"
        case .coreMismatch(let path): return "补丁指定的原版核心 SHA-256 校验不匹配：\(path)；补丁未安装，原版资源保持不变。"
        }
    }
}

enum MobilePatchManager {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MobilePatch", isDirectory: true)
    }
    private static var active: URL { folder.appendingPathComponent("active", isDirectory: true) }
    private static var backup: URL { folder.appendingPathComponent("previous", isDirectory: true) }

    private static func manifest(in root: URL) -> MobilePatchManifest? {
        let url = root.appendingPathComponent("mobile-patch.json")
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) <= 32_768,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MobilePatchManifest.self, from: data)
    }

    static var activeSummary: String {
        guard let m = manifest(in: active), m.format == "shiguang-mobile-patch-v1" else {
            return "未安装手机适配补丁"
        }
        let unlockedCore = m.files.contains("dll/SGCore.swf") &&
            (m.targetRevision == nil || m.targetRevision == "") && m.originalSHA256 == nil
        return "\(m.name) · v\(m.version) · 覆盖 \(m.files.count) 个资源" +
            (unlockedCore ? " · 跨版本核心补丁（需自行验证兼容性）" : "")
    }

    /// A patch without targetRevision and originalSHA256 is intentionally
    /// revision-independent. Keep checking SHA-256 for older pinned patches;
    /// never silently bypass an explicit hash supplied by the patch author.
    /// This cannot guarantee future SGCore ABI compatibility: an unlocked
    /// core overlay may need replacement after a game resource update.
    private static func mismatchedCore(_ m: MobilePatchManifest, gameRoot: URL) -> String? {
        let originals = m.files.filter { $0 == "dll/SGCore.swf" }
        guard !originals.isEmpty else { return nil }
        guard let hashes = m.originalSHA256 else { return nil }
        let base = gameRoot.resolvingSymlinksInPath()
        for path in originals {
            guard let expected = hashes[path]?.lowercased(),
                  expected.count == 64,
                  expected.unicodeScalars.allSatisfy({ (48...57).contains(Int($0.value)) || (97...102).contains(Int($0.value)) }) else {
                return path
            }
            let original = base.appendingPathComponent(path).resolvingSymlinksInPath()
            guard original.path.hasPrefix(base.path + "/"),
                  let values = try? original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let bytes = try? Data(contentsOf: original, options: .mappedIfSafe) else { return path }
            let actual = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            if actual != expected { return path }
        }
        return nil
    }

    static func activeRoot(currentRevision: String?, gameRoot: URL) -> URL? {
        guard let m = manifest(in: active), m.format == "shiguang-mobile-patch-v1",
              !m.files.isEmpty else { return nil }
        if let expected = m.targetRevision, !expected.isEmpty,
           expected != currentRevision { return nil }
        if let mismatch = mismatchedCore(m, gameRoot: gameRoot) {
            LaunchDiagnostics.log("[手机补丁] 核心覆盖拒绝启用：原始 SHA-256 不匹配，\(mismatch)")
            return nil
        }
        return active.resolvingSymlinksInPath()
    }

    // Resource overlays preserve the v1 whitelist. v1.08 Build130 also permits
    // exactly one named core SWF, including revision-independent patches;
    // never permit arbitrary DLLs, login, configs, HTML, JS or engines.
    static func permitted(_ path: String) -> Bool {
        guard path.count <= 240, !path.hasPrefix("/"),
              !path.contains("\\"), !path.contains("%"),
              !path.unicodeScalars.contains(where: { $0.value < 32 }) else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return false }
        if path == "dll/SGCore.swf" { return true }
        guard path.hasPrefix("resource/") else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        return ["swf", "png", "jpg", "jpeg", "gif", "webp", "xml", "json", "mp3"].contains(ext)
    }

    static func install(_ source: URL, currentRevision: String?, gameRoot: URL) throws -> String {
        let fm = FileManager.default
        guard ["sgpatch", "zip"].contains(source.pathExtension.lowercased()) else {
            throw MobilePatchError.invalidFormat
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let temp = folder.appendingPathComponent("incoming-\(UUID().uuidString).zip")
        let staged = folder.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fm.removeItem(at: temp)
            try? fm.removeItem(at: staged)
        }
        try fm.copyItem(at: source, to: temp)
        let handle = try FileHandle(forReadingFrom: temp)
        let signature = try handle.read(upToCount: 4) ?? Data()
        try handle.close()
        guard signature.starts(with: [0x50, 0x4B, 0x03, 0x04]) else {
            throw MobilePatchError.invalidFormat
        }
        guard let archive = try? Archive(url: temp, accessMode: .read) else {
            throw MobilePatchError.invalidArchive
        }
        var filePaths = Set<String>()
        var caseInsensitivePaths = Set<String>()
        var totalBytes: UInt64 = 0
        for entry in archive {
            let name = entry.path
            // Directories are checked too: never skip ZIP path traversal checks.
            let bare = name.hasSuffix("/") ? String(name.dropLast()) : name
            guard !bare.hasPrefix("/"), !bare.contains("\\"), !bare.contains("%"),
                  !bare.unicodeScalars.contains(where: { $0.value < 32 }),
                  bare.split(separator: "/", omittingEmptySubsequences: false)
                      .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw MobilePatchError.unsafePath(name)
            }
            if entry.type == .directory {
                guard bare == "resource" || bare.hasPrefix("resource/") else {
                    throw MobilePatchError.unsafePath(name)
                }
                continue
            }
            guard entry.type == .file else { throw MobilePatchError.unsafePath(name) }
            guard name == "mobile-patch.json" || permitted(name) else {
                throw MobilePatchError.unsafePath(name)
            }
            guard filePaths.insert(name).inserted,
                  caseInsensitivePaths.insert(name.lowercased()).inserted else {
                throw MobilePatchError.unsafePath(name)
            }
            totalBytes += UInt64(entry.uncompressedSize)
            if filePaths.count > 2049 || totalBytes > 512 * 1024 * 1024 {
                throw MobilePatchError.oversized
            }
        }
        guard filePaths.contains("mobile-patch.json") else {
            throw MobilePatchError.invalidManifest
        }
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        // ZIPFoundation checks CRC32 for every extracted member by default.
        try fm.unzipItem(at: temp, to: staged, skipCRC32: false)
        guard let m = manifest(in: staged),
              m.format == "shiguang-mobile-patch-v1",
              !m.name.isEmpty, m.name.count <= 80,
              !m.version.isEmpty, m.version.count <= 32 else {
            throw MobilePatchError.invalidManifest
        }
        if let target = m.targetRevision, !target.isEmpty, target != currentRevision {
            throw MobilePatchError.incompatible(target)
        }
        guard !m.files.isEmpty else { throw MobilePatchError.noAssets }
        if let mismatch = mismatchedCore(m, gameRoot: gameRoot) {
            throw MobilePatchError.coreMismatch(mismatch)
        }
        let listed = Set(m.files)
        guard listed.count == m.files.count, listed == filePaths.subtracting(["mobile-patch.json"]),
              m.files.allSatisfy({ permitted($0) }) else {
            throw MobilePatchError.invalidManifest
        }
        for path in m.files {
            let file = staged.appendingPathComponent(path).resolvingSymlinksInPath()
            guard file.path.hasPrefix(staged.resolvingSymlinksInPath().path + "/"),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else {
                throw MobilePatchError.invalidFile(path)
            }
            // Reject malformed core SWF archives even for revision-independent patches.
            if path == "dll/SGCore.swf" {
                guard (values.fileSize ?? 0) >= 64 else { throw MobilePatchError.invalidFile(path) }
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                let magic = try handle.read(upToCount: 3) ?? Data()
                guard ["FWS", "CWS", "ZWS"].contains(String(data: magic, encoding: .ascii) ?? "") else {
                    throw MobilePatchError.invalidFile(path)
                }
            }
        }
        if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
        let hasOld = fm.fileExists(atPath: active.path)
        if hasOld { try fm.moveItem(at: active, to: backup) }
        do {
            try fm.moveItem(at: staged, to: active)
        } catch {
            if hasOld { try? fm.moveItem(at: backup, to: active) }
            throw error
        }
        if hasOld { try? fm.removeItem(at: backup) }
        if m.files.contains("dll/SGCore.swf") && m.targetRevision == nil && m.originalSHA256 == nil {
            LaunchDiagnostics.log("[手机补丁] 通用核心覆盖：未绑定资源修订或原核心 SHA-256；如资源包升级后异常，请撤销补丁")
        }
        LaunchDiagnostics.log("[手机补丁] 已原子启用 \(m.name) v\(m.version)，\(m.files.count) 个资源；原 Game 文件未修改")
        return activeSummary
    }

    static func clear() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: active.path) { try fm.removeItem(at: active) }
        LaunchDiagnostics.log("[手机补丁] 已撤销覆盖层，原 Game 资源未修改")
    }
}
