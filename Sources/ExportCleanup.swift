import Foundation
import ImageIO

/// Raw values are days; zero disables automatic cleanup. Manual cleanup is separate.
enum ExportRetentionPolicy: Int, CaseIterable {
    case never = 0, oneDay = 1, threeDays = 3, sevenDays = 7, thirtyDays = 30
    static let `default` = ExportRetentionPolicy.threeDays
}

/// A preview is a fixed set, so confirmation never authorizes files created later.
struct ExportCleanupPlan {
    fileprivate let directory: URL
    fileprivate let directoryIdentity: ExportFileIdentity
    fileprivate let records: [OwnedExportRecord]
    fileprivate let hadManifest: Bool
    fileprivate let mode: ExportCleanup.Mode
    fileprivate let eligible: [OwnedExportRecord]
    let protectedCount: Int
    let untrackedCount: Int
    let changedCount: Int
    var count: Int { eligible.count }
    var byteCount: UInt64 { eligible.reduce(0) { $0 + $1.identity.size } }
    var legacyCount: Int { eligible.filter { $0.isLegacy }.count }
    var urls: [URL] { eligible.map { directory.appendingPathComponent($0.name) } }
}

struct ExportCleanupResult {
    struct Failure {
        let url: URL
        let message: String
    }
    var movedCount = 0
    var movedBytes: UInt64 = 0
    var skippedCount = 0
    var failures: [Failure] = []
}

/// Only moves verified copied exports to Trash. Never recursively traverses or
/// deletes anything. The caller must confirm a manual .allOwned preview first.
struct ExportCleanup {
    enum Mode { case expired(ExportRetentionPolicy), allOwned }
    static let freshProtectionInterval: TimeInterval = 5 * 60
    private let directory: URL?
    private let trash: (URL) throws -> Void
    private let currentProtectedPath: () -> String?

    init(directory: URL? = nil,
         trash: @escaping (URL) throws -> Void = ExportCleanup.moveToTrash,
         currentProtectedPath: @escaping () -> String? = { nil }) {
        self.directory = directory
        self.trash = trash
        self.currentProtectedPath = currentProtectedPath
    }

    func plan(mode: Mode, protectedPath: String? = nil, now: Date = Date()) throws -> ExportCleanupPlan {
        try OwnedExportRegistry.withLock {
            let directory = try self.directory ?? CopiedImageStore.exportsDirectory()
            let exists = try OwnedExportRegistry.validateDirectory(directory, create: false)
            let state = exists ? try OwnedExportRegistry.read(directory: directory) : OwnedExportRegistry.State(records: [], exists: false)
            let identity = exists ? try ExportFileIdentity.read(directory) : .missing
            var eligible: [OwnedExportRecord] = []
            var protectedCount = 0
            var changedCount = 0
            for record in state.records {
                let url = directory.appendingPathComponent(record.name)
                guard try OwnedExportRegistry.matches(record, at: url) else { changedCount += 1; continue }
                if Self.isProtected(record, url: url, paths: [protectedPath, currentProtectedPath()], now: now) {
                    protectedCount += 1
                } else if Self.isEligible(record, mode: mode, now: now) {
                    eligible.append(record)
                }
            }
            let names = Set(state.records.map { $0.name })
            let entries = exists ? try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) : []
            return ExportCleanupPlan(directory: directory, directoryIdentity: identity, records: state.records,
                                     hadManifest: state.exists, mode: mode, eligible: eligible,
                                     protectedCount: protectedCount,
                                     untrackedCount: entries.filter { !names.contains($0.lastPathComponent) }.count,
                                     changedCount: changedCount)
        }
    }

    /// Revalidates ownership, current clipboard, age, and filesystem identity
    /// after the confirmation dialog. Newly eligible files require a new preview.
    func run(_ plan: ExportCleanupPlan, protectedPath: String? = nil, now: Date = Date()) throws -> ExportCleanupResult {
        try OwnedExportRegistry.withLock {
            var result = ExportCleanupResult()
            guard !plan.eligible.isEmpty else { return result }
            let directory = try self.directory ?? CopiedImageStore.exportsDirectory()
            guard directory.standardizedFileURL == plan.directory.standardizedFileURL,
                  try OwnedExportRegistry.validateDirectory(directory, create: false),
                  try ExportFileIdentity.read(directory).sameFile(as: plan.directoryIdentity) else {
                throw ExportStorageError.unsafeDirectory(directory.path)
            }
            var state = try OwnedExportRegistry.read(directory: directory)
            // A removed registry must not turn previously tracked names into legacy files.
            if plan.hadManifest && !state.exists { throw ExportStorageError.changedManifest }
            if !state.exists { state.records = plan.records }
            for record in plan.eligible {
                let url = directory.appendingPathComponent(record.name)
                do {
                    guard state.records.contains(record),
                          try OwnedExportRegistry.validateDirectory(directory, create: false),
                          try ExportFileIdentity.read(directory).sameFile(as: plan.directoryIdentity),
                          try OwnedExportRegistry.matches(record, at: url),
                          !Self.isProtected(record, url: url, paths: [protectedPath, currentProtectedPath()], now: now),
                          Self.isEligible(record, mode: plan.mode, now: now) else {
                        result.skippedCount += 1
                        continue
                    }
                    try trash(url)
                    // Never claim success if a no-op injected/failed mover leaves the source.
                    if try OwnedExportRegistry.itemExists(url) { throw ExportStorageError.trashDidNotMove }
                    result.movedCount += 1
                    result.movedBytes += record.identity.size
                    state.records.removeAll { $0 == record }
                } catch {
                    result.failures.append(.init(url: url, message: error.localizedDescription))
                }
            }
            do {
                guard try OwnedExportRegistry.validateDirectory(directory, create: false),
                      try ExportFileIdentity.read(directory).sameFile(as: plan.directoryIdentity) else {
                    throw ExportStorageError.unsafeDirectory(directory.path)
                }
                try OwnedExportRegistry.write(state.records, directory: directory)
            }
            catch { result.failures.append(.init(url: OwnedExportRegistry.manifestURL(directory), message: error.localizedDescription)) }
            return result
        }
    }

    static func moveToTrash(_ url: URL) throws {
        _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private static func isEligible(_ record: OwnedExportRecord, mode: Mode, now: Date) -> Bool {
        switch mode {
        case .allOwned: return true
        case .expired(let policy):
            guard policy != .never else { return false }
            // Strict cutoff: a file exactly N days old is retained until it is older.
            return record.createdAt < now.addingTimeInterval(-Double(policy.rawValue) * 86_400)
        }
    }

    private static func isProtected(_ record: OwnedExportRecord, url: URL, paths: [String?], now: Date) -> Bool {
        let newestDate = max(record.createdAt, record.identity.modifiedAt)
        if newestDate >= now.addingTimeInterval(-freshProtectionInterval) { return true }
        return paths.compactMap { $0 }.contains { path in
            guard path.hasPrefix("/") else { return false }
            // Resolve only for comparison; never use this result as a cleanup target.
            return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL
        }
    }
}

fileprivate struct ExportFileIdentity: Codable, Equatable {
    let device: UInt64
    let inode: UInt64
    let size: UInt64
    let modifiedAt: Date
    static let missing = ExportFileIdentity(device: 0, inode: 0, size: 0, modifiedAt: .distantPast)

    static func read(_ url: URL, regularFile: Bool = false) throws -> ExportFileIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let type = attributes[.type] as? FileAttributeType
        guard type != .typeSymbolicLink,
              !regularFile || (type == .typeRegular && (attributes[.referenceCount] as? NSNumber)?.intValue == 1),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { throw ExportStorageError.unsafeFile }
        return ExportFileIdentity(device: device.uint64Value, inode: inode.uint64Value,
                                  size: size.uint64Value, modifiedAt: modified)
    }
    func sameFile(as other: ExportFileIdentity) -> Bool { device == other.device && inode == other.inode }
}

fileprivate struct OwnedExportRecord: Codable, Equatable {
    let name: String
    let createdAt: Date
    let identity: ExportFileIdentity
    let isLegacy: Bool
}

/// The sibling registry keeps Exports PNG-only and limits legacy adoption to one
/// initial snapshot. Afterwards an unknown filename is never proof of ownership.
enum OwnedExportRegistry {
    private static let lock = NSRecursiveLock()
    fileprivate struct State { var records: [OwnedExportRecord]; let exists: Bool }
    private struct Manifest: Codable { let version: Int; let records: [OwnedExportRecord] }
    private static let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])

    static func withLock<T>(_ action: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try action()
    }

    /// Walk components without following symlinks. In particular, never normalize
    /// a redirected Exports folder into an unrelated user folder before saving.
    @discardableResult
    static func validateDirectory(_ directory: URL, create: Bool) throws -> Bool {
        guard directory.isFileURL, directory.path.hasPrefix("/"),
              !directory.pathComponents.contains("..") else { throw ExportStorageError.unsafeDirectory(directory.path) }
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in directory.pathComponents.dropFirst() {
            current.appendPathComponent(component, isDirectory: true)
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw ExportStorageError.unsafeDirectory(current.path) }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                if !create { return false }
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
                let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw ExportStorageError.unsafeDirectory(current.path) }
            }
        }
        return true
    }

    static func itemExists(_ url: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return false
        }
    }

    static func prepareForSave(directory: URL) throws {
        try withLock {
            let state = try read(directory: directory)
            if !state.exists { try write(state.records, directory: directory) }
        }
    }

    static func register(_ url: URL, createdAt: Date) throws {
        try withLock {
            let directory = url.deletingLastPathComponent()
            guard try validateDirectory(directory, create: false), validFilename(url.lastPathComponent) != nil else {
                throw ExportStorageError.unsafeFile
            }
            var state = try read(directory: directory)
            let record = OwnedExportRecord(name: url.lastPathComponent, createdAt: createdAt,
                                           identity: try ExportFileIdentity.read(url, regularFile: true), isLegacy: false)
            state.records.removeAll { $0.name == record.name }
            state.records.append(record)
            try write(state.records, directory: directory)
        }
    }

    static func manifestURL(_ directory: URL) -> URL {
        directory.deletingLastPathComponent().appendingPathComponent(".\(directory.lastPathComponent).aprilshot-owned-v1.json")
    }

    fileprivate static func read(directory: URL) throws -> State {
        let manifest = manifestURL(directory)
        do {
            let identity = try ExportFileIdentity.read(manifest, regularFile: true)
            guard identity.size <= 16 * 1024 * 1024 else { throw ExportStorageError.invalidManifest }
            let decoded = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifest))
            guard decoded.version == 1,
                  Set(decoded.records.map { $0.name }).count == decoded.records.count,
                  decoded.records.allSatisfy({ validFilename($0.name) != nil && $0.createdAt.timeIntervalSince1970.isFinite }) else {
                throw ExportStorageError.invalidManifest
            }
            return State(records: decoded.records, exists: true)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return State(records: try legacyRecords(directory: directory), exists: false)
        }
    }

    fileprivate static func write(_ records: [OwnedExportRecord], directory: URL) throws {
        guard try validateDirectory(directory, create: false) else { throw ExportStorageError.unsafeDirectory(directory.path) }
        let manifest = manifestURL(directory)
        // A pre-existing symlink, directory, or hard link is never followed/replaced.
        do { _ = try ExportFileIdentity.read(manifest, regularFile: true) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { /* first registry */ }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Manifest(version: 1, records: records.sorted { $0.name < $1.name })).write(to: manifest, options: .atomic)
    }

    fileprivate static func matches(_ record: OwnedExportRecord, at url: URL) throws -> Bool {
        do {
            return try ExportFileIdentity.read(url, regularFile: true) == record.identity
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return false
        } catch is ExportStorageError {
            return false
        }
    }

    private static func legacyRecords(directory: URL) throws -> [OwnedExportRecord] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try files.compactMap { url in
            guard let namedAt = validFilename(url.lastPathComponent) else { return nil }
            let identity: ExportFileIdentity
            do { identity = try ExportFileIdentity.read(url, regularFile: true) }
            catch is ExportStorageError { return nil }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
            guard identity.size >= 8 else { return nil }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            guard try file.read(upToCount: 8) == pngSignature,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetType(source) as String? == "public.png",
                  CGImageSourceGetCount(source) == 1,
                  CGImageSourceGetStatus(source) == .statusComplete,
                  CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil,
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                  try ExportFileIdentity.read(url, regularFile: true) == identity else { return nil }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let created = (attributes[.creationDate] as? Date) ?? identity.modifiedAt
            return OwnedExportRecord(name: url.lastPathComponent,
                                     createdAt: max(namedAt, max(created, identity.modifiedAt)),
                                     identity: identity, isLegacy: true)
        }
    }

    private static func validFilename(_ name: String) -> Date? {
        let pattern = "^AprilShot_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\\.png$"
        guard let match = name.range(of: pattern, options: .regularExpression),
              match == name.startIndex..<name.endIndex else { return nil }
        let stamp = String(name.dropFirst("AprilShot_".count).prefix(19))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.isLenient = false
        guard let date = formatter.date(from: stamp), formatter.string(from: date) == stamp else { return nil }
        return date
    }
}

enum ExportStorageError: LocalizedError {
    case unsafeDirectory(String)
    case unsafeFile, invalidManifest, changedManifest, trashDidNotMove
    var errorDescription: String? {
        switch self {
        case .unsafeDirectory(let path): return "图片文件夹路径已变化或包含符号链接；为保护其他文件，已停止操作。\n路径：\(path)"
        case .unsafeFile: return "图片或清理记录不是可安全处理的独立普通文件。"
        case .invalidManifest: return "图片清理记录无法识别；已保留全部图片。"
        case .changedManifest: return "图片清理记录已变化；请重新打开清理预览。"
        case .trashDidNotMove: return "图片未能移到废纸篓，原文件已保留。"
        }
    }
}
