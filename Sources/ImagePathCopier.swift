import AppKit

/// Copied PNGs are persistent exports with registered ownership. Retention and
/// explicit cleanup may move old copies to Trash; user-selected Save files are separate.
struct CopiedImageStore {
    private let directory: URL?

    init(directory: URL? = nil) { self.directory = directory }

    static func exportsDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("AprilShot", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
    }

    func savePNG(_ data: Data) throws -> URL {
        try OwnedExportRegistry.withLock {
            let destination = try directory ?? Self.exportsDirectory()
            try OwnedExportRegistry.validateDirectory(destination, create: true)
            // Snapshot legacy ownership before creating the first newly tracked file.
            try OwnedExportRegistry.prepareForSave(directory: destination)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let createdAt = Date()
            // UUID avoids replacing an older copy, including copies in the same second.
            let name = "AprilShot_\(formatter.string(from: createdAt))_\(UUID().uuidString).png"
            let url = destination.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw CocoaError(.fileReadNoPermission)
            }
            // Record ownership before publishing its path. A registry failure leaves
            // the PNG intact and, like every storage failure, preserves the clipboard.
            try OwnedExportRegistry.register(url, createdAt: createdAt)
            return url
        }
    }
}

struct ImagePathCopier {
    private let store: CopiedImageStore
    private let writePath: (String) -> Bool

    init(store: CopiedImageStore = CopiedImageStore(),
         writePath: @escaping (String) -> Bool = ImagePathCopier.writeToGeneralPasteboard) {
        self.store = store
        self.writePath = writePath
    }

    /// Store first. A storage failure must not clear or replace the clipboard.
    /// Only plain path text is offered, so terminal paste cannot prefer an image
    /// flavor or a file:// URL. This is prompt text, not a shell command.
    func copyPNG(_ data: Data) throws -> URL {
        let url: URL
        do { url = try store.savePNG(data) }
        catch { throw CopyError.saveFailed(error.localizedDescription) }
        guard writePath(url.path) else { throw CopyError.clipboardFailed(url) }
        return url
    }

    static func writeToGeneralPasteboard(_ path: String) -> Bool {
        write(path, to: .general)
    }

    static func write(_ path: String, to pasteboard: NSPasteboard) -> Bool {
        let item = NSPasteboardItem()
        guard item.setString(path, forType: .string) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    enum CopyError: LocalizedError {
        case saveFailed(String), clipboardFailed(URL)
        var errorDescription: String? {
            switch self {
            case .saveFailed(let reason):
                return "无法保存标注 PNG，剪贴板未更改：\(reason)\n请检查磁盘空间和文件夹权限，或点击“保存”选择其他位置。"
            case .clipboardFailed(let url):
                return "图片已保留，但无法复制路径到剪贴板，请重试。\n图片位置：\(url.path)"
            }
        }
    }
}
