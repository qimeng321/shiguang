import Foundation
import ZIPFoundation

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

    var canStartGame: Bool { gameRoot != nil && !selectedEntry.isEmpty && !isImporting && !isClearing }
    var hasInstalledPackage: Bool { gameRoot != nil }

    init() {
        let root = Self.savedGameRoot
        if FileManager.default.fileExists(atPath: root.path) {
            gameRoot = root
            entries = Self.findEntries(in: root)
            selectedEntry = Self.preferredEntry(in: entries)
            status = entries.isEmpty ? "已安装资源，但没有找到 SWF 游戏入口。" : "美化包已就绪，可以进入游戏。"
        }
    }

    // Backup path when a third-party Files provider makes a .srom file gray in
    // the system importer. UIFileSharingEnabled exposes Documents in Files.
    func refreshLocalPackages() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folders = [documents, documents.appendingPathComponent("Inbox", isDirectory: true)]
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
                    self.status = "美化包导入成功，已识别 \(entries.count) 个游戏入口，可点击“进入游戏”。"
                    self.isImporting = false
                }
            } catch {
                await MainActor.run {
                    self.status = "导入失败：\(error.localizedDescription)"
                    self.isImporting = false
                }
            }
        }
    }


    func clearPackage() {
        guard !isImporting && !isClearing else { return }
        isClearing = true
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

        if manager.fileExists(atPath: backup.path) {
            try manager.removeItem(at: backup)
        }
        let existing = manager.fileExists(atPath: savedGameRoot.path)
        if existing { try manager.moveItem(at: savedGameRoot, to: backup) }
        do {
            try manager.moveItem(at: staging, to: savedGameRoot)
            if existing { try? manager.removeItem(at: backup) }
        } catch {
            if existing { try? manager.moveItem(at: backup, to: savedGameRoot) }
            throw error
        }
        return entries
    }

    private nonisolated static func findEntries(in root: URL) -> [String] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "swf",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            result.append(relative)
        }
        let candidates = result.filter { path in
            ["client.swf", "main.swf", "game.swf"].contains(path.lastPathComponent.lowercased())
        }
        let launchable = candidates.isEmpty
            ? result.filter { $0.split(separator: "/").count <= 2 }
            : candidates
        return launchable.sorted { a, b in
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
