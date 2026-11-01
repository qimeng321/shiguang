import Foundation
import ZIPFoundation

enum ImportError: LocalizedError {
    case invalidArchive
    case unsafeEntry(String)
    case noGameFiles
    case invalidPackage

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "文件不是可读取的 ZIP/.srom 压缩包。"
        case .unsafeEntry(let path): return "资源包含不安全路径：\(path)"
        case .noGameFiles: return "资源包内没有找到 SWF。请确认这是完整的游戏资源包。"
        case .invalidPackage: return "找不到已导入的游戏资源。"
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var status = "导入当前游戏资源包后选择启动文件。"
    @Published var isImporting = false
    @Published var entries: [String] = []
    @Published var selectedEntry = ""
    @Published var gameRoot: URL?

    init() {
        let root = Self.savedGameRoot
        if FileManager.default.fileExists(atPath: root.path) {
            gameRoot = root
            entries = Self.findEntries(in: root)
            selectedEntry = Self.preferredEntry(in: entries)
            status = entries.isEmpty ? "已导入资源，但没有找到 SWF 入口。" : "资源已就绪，选择入口后启动。"
        }
    }

    func importPackage(_ source: URL) {
        guard !isImporting else { return }
        isImporting = true
        status = "正在校验并解压资源包，可能需要几分钟…"
        Task.detached(priority: .userInitiated) {
            do {
                let entries = try Self.extractPackage(source)
                await MainActor.run {
                    self.gameRoot = Self.savedGameRoot
                    self.entries = entries
                    self.selectedEntry = Self.preferredEntry(in: entries)
                    self.status = "资源导入完成，找到 \(entries.count) 个 SWF 文件。"
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

    private nonisolated static var savedGameRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Game", isDirectory: true)
    }

    private nonisolated static func extractPackage(_ source: URL) throws -> [String] {
        let manager = FileManager.default
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

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
