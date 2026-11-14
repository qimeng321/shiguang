import Foundation
import CryptoKit
import ZIPFoundation

/// Updates game files listed in ZIP-structured .zip/.srom archives, with an on-disk rollback journal.
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
    case busyOrRecovery(String), rollbackFailed(String), fullGamePackage

    var errorDescription: String? {
        switch self {
        case .missingGame: return "请先导入完整的游戏资源包，再使用增量更新。"
        case .badExtension: return "增量包仅支持 .zip 或 .srom 扩展名，且文件内容必须是 ZIP 格式。"
        case .invalidArchive: return "增量包不是有效 ZIP 压缩内容，或解压、CRC32 校验失败；非 ZIP 格式的 .srom 暂不支持。"
        case .unsafeFile(let path): return "增量包包含不安全或不支持的文件：\(String(path.prefix(100)))"
        case .unsupportedSize: return "增量包超出安全限制（最多 2000 个文件、300 MB 解压体积）；完整游戏包请通过“导入美化包”安装。"
        case .missingCore: return "增量包不包含可更新的游戏文件；请选择包含游戏资源的 ZIP 或 SROM 包。"
        case .invalidRevision: return "无法从增量包识别有效的核心修订号。"
        case .upToDate(let revision): return "当前资源已是 \(revision)，无需重复更新。"
        case .downgrade(let from, let to): return "更新包版本 \(to) 低于现有版本 \(from)，已阻止覆盖。"
        case .invalidGameFile(let path): return "游戏资源状态异常，更新已中止：\(path)"
        case .noSpace: return "手机可用空间不足以暂存增量文件和回滚备份。请释放存储空间后重试。"
        case .busyOrRecovery(let details): return "存在尚未完成的增量更新：\(details)"
        case .rollbackFailed(let details): return "无法完整恢复部分资源：\(details)。请保留增量备份并联系开发者。"
        case .fullGamePackage: return "检测到完整游戏入口 Client.swf 或根目录 index.html；请通过“导入美化包”安装，以免覆盖启动入口。"
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
        let targetRevision: String?
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
        let current = LaunchDiagnostics.coreRevision(root: gameRoot, entry: entry) ?? "未知"
        // Resource-only patches may have no dll.xml and are not tied to a
        // specific revision. Same-revision patches are valid too.
        if let target = checked.targetRevision,
           let currentValue = UInt64(current), let targetValue = UInt64(target),
           currentValue > targetValue {
            throw GameIncrementalError.downgrade(current, target)
        }
        let target = checked.targetRevision ?? current
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
            targetRevision: target,
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
            // Only versioned deltas carry dll.xml. For resource-only updates
            // keep the installed core revision unchanged.
            if let target = checked.targetRevision {
                guard revision(from: try Data(contentsOf: stage.appendingPathComponent("config/dll.xml"))) == target else {
                    throw GameIncrementalError.invalidRevision
                }
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
                let installedRevision = LaunchDiagnostics.coreRevision(root: gameRoot, entry: entry)
                let matchesRevision = checked.targetRevision == nil || installedRevision == checked.targetRevision
                guard matchesRevision,
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
        guard ["zip", "srom"].contains(url.pathExtension.lowercased()) else {
            throw GameIncrementalError.badExtension
        }
        let stats = try fm.attributesOfItem(atPath: url.path)
        let archiveBytes = (stats[.size] as? NSNumber)?.uint64Value ?? 0
        guard archiveBytes > 128 && archiveBytes <= maxArchiveBytes else { throw GameIncrementalError.unsupportedSize }
        // .srom is an extension, not a compression format: accept ZIP-backed
        // .srom only. Non-ZIP formats require an explicit decoder, never a guess.
        guard let signatureHandle = try? FileHandle(forReadingFrom: url) else {
            throw GameIncrementalError.invalidArchive
        }
        let signature = (try? signatureHandle.read(upToCount: 4)) ?? Data()
        try? signatureHandle.close()
        guard signature.starts(with: [0x50, 0x4B, 0x03, 0x04]) ||
              signature.starts(with: [0x50, 0x4B, 0x05, 0x06]) ||
              signature.starts(with: [0x50, 0x4B, 0x07, 0x08]) else {
            throw GameIncrementalError.invalidArchive
        }
        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw GameIncrementalError.invalidArchive
        }
        var paths: [String] = []
        var entries: [String: Entry] = [:]
        var lowered = Set<String>()
        var totalBytes: UInt64 = 0
        for entry in archive {
            let path = entry.path
            // Never merge a full package into Game from the incremental entry.
            // These files belong to the full .srom importer, not the delta updater.
            if path == "Client.swf" || path == "index.html" {
                throw GameIncrementalError.fullGamePackage
            }
            if entry.type == .directory {
                let prefix = path.hasSuffix("/") ? String(path.dropLast()) : path
                guard safeComponents(prefix), permittedDirectory(prefix) else {
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
        // A valid incremental ZIP may update *only* login, module, maps,
        // sprites, scripts or another resource. Requiring SGCore/dll.xml for
        // every patch incorrectly rejects these ordinary delta archives.
        guard !paths.isEmpty else { throw GameIncrementalError.missingCore }
        var revisionValue: String? = nil
        if let config = entries["config/dll.xml"] {
            guard config.uncompressedSize <= 128 * 1024 else { throw GameIncrementalError.invalidRevision }
            var xml = Data()
            do {
                _ = try archive.extract(config, consumer: { bytes in xml.append(bytes) })
            } catch { throw GameIncrementalError.invalidArchive }
            guard let target = revision(from: xml) else { throw GameIncrementalError.invalidRevision }
            revisionValue = target
        }
        LaunchDiagnostics.log("[增量更新] 检测到\\(paths.count)个资源文件；目标修订号=\\(revisionValue ?? "保持当前")")
        return CheckedArchive(paths: paths, entries: entries, totalBytes: totalBytes,
                              targetRevision: revisionValue)
    }

    private static func revision(from data: Data) -> String? {
        guard let xml = String(data: data, encoding: .utf8),
              let after = xml.components(separatedBy: "ver=\\\"").dropFirst().first else { return nil }
        let value = String(after.prefix(while: { $0.isNumber }))
        // The resource pack's own dll.xml carries the version. Keep basic
        // structural validation but do not lock the updater to one core name.
        guard (6...12).contains(value.count), UInt64(value) != nil,
              xml.contains(".swf?" + value) else { return nil }
        return value
    }

    private static func permittedDirectory(_ path: String) -> Bool {
        // ZIP metadata and hidden files are not part of the game. Refuse
        // platform bundles and hidden paths even when the parent is safe.
        let chunks = path.split(separator: "/")
        return !chunks.isEmpty && chunks.allSatisfy {
            !$0.hasPrefix(".") && $0 != "__MACOSX" && $0 != "Payload"
                && !$0.lowercased().hasSuffix(".app")
        }
    }

    private static func safeComponents(_ path: String) -> Bool {
        guard !path.isEmpty && path.count <= 240 && !path.hasPrefix("/"),
              !path.contains("\\"), !path.contains("%"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 }) else { return false }
        let chunks = path.split(separator: "/", omittingEmptySubsequences: false)
        return chunks.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func permitted(_ path: String) -> Bool {
        guard safeComponents(path), permittedDirectory(path) else { return false }
        // Do not replace the complete game's entry point through the delta
        // importer; these are handled by the full game import workflow.
        if path == "Client.swf" || path == "index.html" { return false }
        // Broad game-resource extensions, not an obsolete per-folder or
        // per-core filename whitelist. Still no executable native payloads.
        let ext = (path as NSString).pathExtension.lowercased()
        let supported = Set([
            "swf", "xml", "json", "txt", "ini", "cfg",
            "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg",
            "js", "mjs", "css", "wasm", "html", "htm",
            "mp4", "webm", "mp3", "wav", "ogg",
            "otf", "ttf", "woff", "woff2",
            "bin", "dat", "atlas"
        ])
        return supported.contains(ext)
    }

    private static func ensureRegularFile(_ url: URL, path: String) throws {
        guard let meta = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              meta.isRegularFile == true, meta.isSymbolicLink != true else {
            throw GameIncrementalError.invalidGameFile(path)
        }
    }

    private static func ensureSafeAncestors(_ root: URL, relative: String) throws {
        guard permitted(relative) else { throw GameIncrementalError.unsafeFile(relative) }
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
