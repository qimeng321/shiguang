import Foundation
import CryptoKit
import ZIPFoundation

/// Updates only game files listed in a ZIP, with an on-disk rollback journal.
/// The existing multi-GB Game directory is never copied, replaced or deleted.
struct GameIncrementalPreview {
    let currentRevision: String
    let targetRevision: String
    let fileCount: Int
    let overwriteCount: Int
    let addedCount: Int
    let unpackedBytes: UInt64
    let backupBytes: UInt64
}

enum GameIncrementalError: LocalizedError {
    case missingGame, badExtension, invalidArchive, unsafeFile(String)
    case unsupportedSize, missingCore, invalidRevision, upToDate(String)
    case downgrade(String, String), invalidGameFile(String), noSpace
    case busyOrRecovery(String), rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingGame: return "请先导入完整的游戏资源包，再使用增量更新。"
        case .badExtension: return "请选择 ZIP 格式的游戏资源增量包。"
        case .invalidArchive: return "增量包 ZIP 无法读取、解压或 CRC32 校验失败。"
        case .unsafeFile(let path): return "增量包包含不安全或不支持的文件：\(String(path.prefix(100)))"
        case .unsupportedSize: return "增量包超出安全限制（最多 2000 个文件、300 MB 解压体积）。"
        case .missingCore: return "这不是可识别的游戏增量包：缺少 config/dll.xml 或 dll/NieoCore.swf。"
        case .invalidRevision: return "无法从增量包识别有效的核心修订号。"
        case .upToDate(let revision): return "当前资源已是 \(revision)，无需重复更新。"
        case .downgrade(let from, let to): return "更新包版本 \(to) 低于现有版本 \(from)，已阻止覆盖。"
        case .invalidGameFile(let path): return "游戏资源状态异常，更新已中止：\(path)"
        case .noSpace: return "手机可用空间不足以暂存增量文件和回滚备份。请释放存储空间后重试。"
        case .busyOrRecovery(let details): return "存在尚未完成的增量更新：\(details)"
        case .rollbackFailed(let details): return "无法完整恢复部分资源：\(details)。请保留增量备份并联系开发者。"
        }
    }
}

enum GameIncrementalUpdater {
    private static let maxFiles = 2000
    private static let maxTotalBytes: UInt64 = 300 * 1024 * 1024
    private static let maxFileBytes: UInt64 = 80 * 1024 * 1024
    private static let maxArchiveBytes: UInt64 = 300 * 1024 * 1024

    private struct Record: Codable {
        let path: String
        let existed: Bool
    }
    private struct Journal: Codable {
        let currentRevision: String
        let targetRevision: String
        let records: [Record]
        var committed: Bool
    }
    private struct CheckedArchive {
        let paths: [String]
        let entries: [String: Entry]
        let totalBytes: UInt64
        let targetRevision: String
    }

    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameIncremental", isDirectory: true)
    }
    private static var transaction: URL {
        support.appendingPathComponent("current", isDirectory: true)
    }
    private static var journalURL: URL { transaction.appendingPathComponent("journal.json") }
    private static var backupRoot: URL {
        transaction.appendingPathComponent("backup", isDirectory: true)
    }

    /// Always invoke this before permitting a game launch. Never discard an
    /// interrupted transaction without recovering the original files.
    static func recoverIfNeeded(gameRoot: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: transaction.path) else { return }
        guard fm.fileExists(atPath: journalURL.path) else {
            // A staging/backup directory without a journal never touched Game.
            try fm.removeItem(at: transaction)
            return
        }
        let data = try Data(contentsOf: journalURL)
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        guard !journal.records.isEmpty,
              journal.records.count <= maxFiles,
              journal.records.allSatisfy({ permitted($0.path) }) else {
            throw GameIncrementalError.busyOrRecovery("恢复清单无效，不会擅自删除备份")
        }
        if journal.committed {
            try fm.removeItem(at: transaction)
            LaunchDiagnostics.log("[增量更新] 上次安装已提交，旧备份清理完成")
            return
        }
        var errors: [String] = []
        // Undo every change in reverse order. An original absent from backup
        // was never modified because all backups are made before journaling.
        for record in journal.records.reversed() {
            let target = gameRoot.appendingPathComponent(record.path)
            let saved = backupRoot.appendingPathComponent(record.path)
            do {
                try ensureSafeAncestors(gameRoot, relative: record.path)
                if record.existed {
                    guard fm.fileExists(atPath: saved.path) else {
                        throw GameIncrementalError.invalidGameFile(record.path + "：回滚源缺失")
                    }
                    if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                    try fm.copyItem(at: saved, to: target)
                } else if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
            } catch { errors.append("\(record.path)：\(error.localizedDescription)") }
        }
        guard errors.isEmpty else {
            LaunchDiagnostics.log("[增量更新] 回滚不完整，保留恢复日志与旧资源：\(errors.prefix(3).joined(separator: "; "))")
            throw GameIncrementalError.rollbackFailed(errors.prefix(3).joined(separator: "; "))
        }
        try fm.removeItem(at: transaction)
        LaunchDiagnostics.log("[增量更新] 已恢复中断安装的全部原始文件")
    }

    static func inspect(archiveURL: URL, gameRoot: URL, entry: String) throws -> GameIncrementalPreview {
        try checkGame(gameRoot, entry: entry)
        let checked = try checkArchive(archiveURL)
        guard let current = LaunchDiagnostics.coreRevision(root: gameRoot, entry: entry) else {
            throw GameIncrementalError.invalidRevision
        }
        if current == checked.targetRevision { throw GameIncrementalError.upToDate(current) }
        if current > checked.targetRevision { throw GameIncrementalError.downgrade(current, checked.targetRevision) }
        let fm = FileManager.default
        var overwrite = 0
        var existingBytes: UInt64 = 0
        for path in checked.paths {
            try ensureSafeAncestors(gameRoot, relative: path)
            let dst = gameRoot.appendingPathComponent(path)
            if fm.fileExists(atPath: dst.path) {
                try ensureRegularFile(dst, path: path)
                overwrite += 1
                let fileBytes = (try fm.attributesOfItem(atPath: dst.path)[.size] as? NSNumber)?.uint64Value ?? 0
                existingBytes += fileBytes
            }
        }
        return GameIncrementalPreview(currentRevision: current,
            targetRevision: checked.targetRevision,
            fileCount: checked.paths.count, overwriteCount: overwrite,
            addedCount: checked.paths.count - overwrite,
            unpackedBytes: checked.totalBytes, backupBytes: existingBytes)
    }

    static func install(archiveURL: URL, gameRoot: URL, entry: String,
                        onProgress: @escaping (Double, String) -> Void) throws -> GameIncrementalPreview {
        let preview = try inspect(archiveURL: archiveURL, gameRoot: gameRoot, entry: entry)
        let checked = try checkArchive(archiveURL)
        let fm = FileManager.default
        try recoverIfNeeded(gameRoot: gameRoot)
        let free = (try? gameRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        let needed = preview.unpackedBytes + preview.backupBytes + 40 * 1024 * 1024
        guard free >= 0 && UInt64(free) > needed else { throw GameIncrementalError.noSpace }
        try fm.createDirectory(at: transaction, withIntermediateDirectories: true)
        let stage = transaction.appendingPathComponent("staged", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        do {
            onProgress(0.05, "正在解压并验证增量资源")
            try fm.unzipItem(at: archiveURL, to: stage, skipCRC32: false)
            onProgress(0.60, "解压完成，正在核验文件内容")
            var expectedHashes: [String: String] = [:]
            for path in checked.paths {
                let src = stage.appendingPathComponent(path)
                try ensureSafeAncestors(stage, relative: path)
                try ensureRegularFile(src, path: path)
                let signature = try filePrefix(src, count: 3)
                if path.lowercased().hasSuffix(".swf") &&
                    !["FWS", "CWS", "ZWS"].contains(String(data: signature, encoding: .ascii) ?? "") {
                    throw GameIncrementalError.invalidGameFile(path + "：SWF 文件头不正确")
                }
                expectedHashes[path] = try sha256(src)
            }
            guard !fm.fileExists(atPath: stage.appendingPathComponent("Client.swf").path) else {
                throw GameIncrementalError.invalidArchive
            }
            guard revision(from: try Data(contentsOf: stage.appendingPathComponent("config/dll.xml"))) == preview.targetRevision else {
                throw GameIncrementalError.invalidRevision
            }
            let records = checked.paths.map { path in Record(path: path,
                existed: fm.fileExists(atPath: gameRoot.appendingPathComponent(path).path)) }
            for record in records where record.existed {
                let from = gameRoot.appendingPathComponent(record.path)
                let dest = backupRoot.appendingPathComponent(record.path)
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: from, to: dest)
            }
            onProgress(0.72, "回滚备份已准备，正在安装")
            var journal = Journal(currentRevision: preview.currentRevision,
                targetRevision: preview.targetRevision, records: records, committed: false)
            try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
            LaunchDiagnostics.log("[增量更新] 开始写入 \(records.count) 个文件：\(preview.currentRevision) → \(preview.targetRevision)")
            do {
                let sorted = checked.paths.filter { $0 != "config/dll.xml" } + ["config/dll.xml"]
                for (i, path) in sorted.enumerated() {
                    let dest = gameRoot.appendingPathComponent(path)
                    try ensureSafeAncestors(gameRoot, relative: path)
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.moveItem(at: stage.appendingPathComponent(path), to: dest)
                    if i % 20 == 0 || i == sorted.count - 1 {
                        onProgress(0.72 + 0.22 * Double(i + 1) / Double(sorted.count), "已合并 \(i + 1)/\(sorted.count) 个资源")
                    }
                }
                for (i, path) in checked.paths.enumerated() {
                    let installed = gameRoot.appendingPathComponent(path)
                    try ensureRegularFile(installed, path: path)
                    guard try sha256(installed) == expectedHashes[path] else {
                        throw GameIncrementalError.invalidGameFile(path + "：安装后哈希不一致")
                    }
                    if i % 50 == 0 { onProgress(0.94 + 0.05 * Double(i + 1) / Double(checked.paths.count), "正在校验安装结果") }
                }
                guard LaunchDiagnostics.coreRevision(root: gameRoot, entry: entry) == preview.targetRevision,
                      LaunchDiagnostics.validateInstalledPackage(root: gameRoot, entry: entry).isEmpty else {
                    throw GameIncrementalError.invalidGameFile("安装后核心版本或关键资源校验失败")
                }
                journal.committed = true
                try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
                onProgress(1.0, "增量更新完成")
                LaunchDiagnostics.log("[增量更新] 成功安装 \(preview.fileCount) 个文件，版本 \(preview.currentRevision) → \(preview.targetRevision)")
                try? fm.removeItem(at: transaction)
                return preview
            } catch {
                LaunchDiagnostics.log("[增量更新] 文件合并失败，开始从备份回滚：\(error.localizedDescription)")
                do { try recoverIfNeeded(gameRoot: gameRoot) }
                catch { throw GameIncrementalError.rollbackFailed(error.localizedDescription) }
                throw error
            }
        } catch {
            if !fm.fileExists(atPath: journalURL.path) {
                try? fm.removeItem(at: transaction)
            }
            throw error
        }
    }

    private static func checkGame(_ root: URL, entry: String) throws {
        guard entry == "Client.swf", LaunchDiagnostics.validateInstalledPackage(root: root, entry: entry).isEmpty else {
            throw GameIncrementalError.missingGame
        }
        try ensureRegularFile(root.appendingPathComponent(entry), path: entry)
    }

    private static func checkArchive(_ url: URL) throws -> CheckedArchive {
        let fm = FileManager.default
        guard url.pathExtension.lowercased() == "zip" else { throw GameIncrementalError.badExtension }
        let stats = try fm.attributesOfItem(atPath: url.path)
        let archiveBytes = (stats[.size] as? NSNumber)?.uint64Value ?? 0
        guard archiveBytes > 128 && archiveBytes <= maxArchiveBytes else { throw GameIncrementalError.unsupportedSize }
        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw GameIncrementalError.invalidArchive
        }
        var paths: [String] = []
        var entries: [String: Entry] = [:]
        var lowered = Set<String>()
        var totalBytes: UInt64 = 0
        for entry in archive {
            let path = entry.path
            if entry.type == .directory {
                let prefix = path.hasSuffix("/") ? String(path.dropLast()) : path
                guard safeComponents(prefix), ["resource", "module", "dll", "config"].contains(String(prefix.split(separator: "/").first ?? "")) else {
                    throw GameIncrementalError.unsafeFile(path)
                }
                continue
            }
            guard entry.type == .file, permitted(path),
                  lowered.insert(path.lowercased()).inserted else {
                throw GameIncrementalError.unsafeFile(path)
            }
            let n = UInt64(entry.uncompressedSize)
            guard n > 0 && n <= maxFileBytes else { throw GameIncrementalError.unsupportedSize }
            totalBytes += n
            guard totalBytes <= maxTotalBytes else { throw GameIncrementalError.unsupportedSize }
            entries[path] = entry
            paths.append(path)
            guard paths.count <= maxFiles else { throw GameIncrementalError.unsupportedSize }
        }
        guard entries["config/dll.xml"] != nil, entries["dll/NieoCore.swf"] != nil else {
            throw GameIncrementalError.missingCore
        }
        let item = entries["config/dll.xml"]!
        guard item.uncompressedSize <= 128 * 1024 else { throw GameIncrementalError.invalidRevision }
        var xml = Data()
        do {
            _ = try archive.extract(item, consumer: { bytes in xml.append(bytes) })
        } catch { throw GameIncrementalError.invalidArchive }
        guard let target = revision(from: xml) else { throw GameIncrementalError.invalidRevision }
        return CheckedArchive(paths: paths, entries: entries, totalBytes: totalBytes, targetRevision: target)
    }

    private static func revision(from data: Data) -> String? {
        guard let xml = String(data: data, encoding: .utf8),
              let after = xml.components(separatedBy: "ver=\"").dropFirst().first else { return nil }
        let value = String(after.prefix(while: { $0.isNumber }))
        guard value.count == 10, xml.contains("NieoCore.swf?" + value) else { return nil }
        return value
    }

    private static func safeComponents(_ path: String) -> Bool {
        guard !path.isEmpty && path.count <= 240 && !path.hasPrefix("/"),
              !path.contains("\\"), !path.contains("%"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 }) else { return false }
        let chunks = path.split(separator: "/", omittingEmptySubsequences: false)
        return chunks.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func permitted(_ path: String) -> Bool {
        guard safeComponents(path) else { return false }
        let chunks = path.split(separator: "/")
        guard chunks.count >= 2 else { return false }
        let parent = String(chunks[0])
        guard ["resource", "module", "dll", "config"].contains(parent) else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        if parent == "config" { return path == "config/dll.xml" }
        if parent == "dll" { return path == "dll/NieoCore.swf" }
        return ["swf", "xml", "png", "jpg", "jpeg", "webp", "gif"].contains(ext)
    }

    private static func ensureRegularFile(_ url: URL, path: String) throws {
        guard let meta = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              meta.isRegularFile == true, meta.isSymbolicLink != true else {
            throw GameIncrementalError.invalidGameFile(path)
        }
    }

    private static func ensureSafeAncestors(_ root: URL, relative: String) throws {
        guard permitted(relative) || relative == "Client.swf" else { throw GameIncrementalError.unsafeFile(relative) }
        let fm = FileManager.default
        let parentChunks = relative.split(separator: "/").dropLast()
        var part = root
        for component in parentChunks {
            part.appendPathComponent(String(component), isDirectory: true)
            if fm.fileExists(atPath: part.path) {
                guard let vals = try? part.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey]),
                      vals.isDirectory == true, vals.isSymbolicLink != true else {
                    throw GameIncrementalError.unsafeFile(relative)
                }
            }
        }
    }

    private static func filePrefix(_ url: URL, count: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try file.read(upToCount: count) ?? Data()
    }

    private static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
