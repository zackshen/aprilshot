import AppKit
import Carbon

/// Persist Carbon modifier bits, not NSEvent's unrelated raw bit values.
struct HotKeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt32
    init(rawValue: UInt32) { self.rawValue = rawValue }

    static let command = HotKeyModifiers(rawValue: UInt32(cmdKey))
    static let shift = HotKeyModifiers(rawValue: UInt32(shiftKey))
    static let option = HotKeyModifiers(rawValue: UInt32(optionKey))
    static let control = HotKeyModifiers(rawValue: UInt32(controlKey))
    static let supported: HotKeyModifiers = [.command, .shift, .option, .control]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt32.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}

/// A deliberately bounded physical-key shortcut. Labels follow the ANSI key
/// positions, as does Carbon registration; they are not keyboard-layout text.
struct HotKeyShortcut: Codable, Equatable {
    struct Key {
        let keyCode: UInt32
        let displayName: String
        let keyEquivalent: String
    }

    static let supportedKeys: [Key] = {
        let letters: [(String, UInt32)] = [
            ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3),
            ("G", 5), ("H", 4), ("I", 34), ("J", 38), ("K", 40), ("L", 37),
            ("M", 46), ("N", 45), ("O", 31), ("P", 35), ("Q", 12), ("R", 15),
            ("S", 1), ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7),
            ("Y", 16), ("Z", 6)
        ]
        let numbers: [(String, UInt32)] = [
            ("0", 29), ("1", 18), ("2", 19), ("3", 20), ("4", 21),
            ("5", 23), ("6", 22), ("7", 26), ("8", 28), ("9", 25)
        ]
        let functionCodes: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        let printable = (letters + numbers).map {
            Key(keyCode: $0.1, displayName: $0.0, keyEquivalent: $0.0.lowercased())
        }
        let functions = functionCodes.enumerated().map { index, keyCode in
            Key(keyCode: keyCode, displayName: "F\(index + 1)",
                keyEquivalent: String(UnicodeScalar(0xF704 + index)!))
        }
        return printable + functions
    }()

    static let defaultShortcut = try! HotKeyShortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: [.command, .shift])
    static let `default` = defaultShortcut

    let keyCode: UInt32
    let modifiers: HotKeyModifiers

    init(keyCode: UInt32, modifiers: HotKeyModifiers) throws {
        guard Self.supportedKeys.contains(where: { $0.keyCode == keyCode }) else {
            throw ValidationError.unsupportedKey
        }
        guard modifiers.subtracting(.supported).isEmpty else { throw ValidationError.unsupportedModifiers }
        // Single-modifier shortcuts can swallow typing, terminal controls, or
        // ordinary app commands. Require two, including Command or Control.
        guard !modifiers.intersection([.command, .control]).isEmpty,
              modifiers.rawValue.nonzeroBitCount >= 2 else {
            throw ValidationError.insufficientModifiers
        }
        // Preserve editor Copy Path, Save, Undo/Redo, selection/editing and
        // common window/quit commands, including macOS's Shift-Command-Q.
        let reservedCommandKeys: Set<UInt32> = [0, 8, 9, 7, 6, 1, 12, 13, 4, 46]
        if modifiers.contains(.command), reservedCommandKeys.contains(keyCode) {
            throw ValidationError.reservedShortcut
        }
        // Avoid the system screenshot shortcuts even if Carbon accepts one.
        if modifiers == [.command, .shift], [UInt32(20), 21, 23].contains(keyCode) {
            throw ValidationError.reservedShortcut
        }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) throws {
        var modifiers: HotKeyModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        try self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(keyCode: values.decode(UInt32.self, forKey: .keyCode),
                      modifiers: values.decode(HotKeyModifiers.self, forKey: .modifiers))
    }

    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.command) { result += "⌘" }
        if modifiers.contains(.shift) { result += "⇧" }
        return result + (Self.supportedKeys.first { $0.keyCode == keyCode }?.displayName ?? "")
    }
    var keyEquivalent: String {
        Self.supportedKeys.first { $0.keyCode == keyCode }?.keyEquivalent ?? ""
    }
    var keyEquivalentModifierMask: NSEvent.ModifierFlags { modifiers.eventFlags }

    enum ValidationError: LocalizedError {
        case unsupportedKey, unsupportedModifiers, insufficientModifiers, reservedShortcut
        var errorDescription: String? {
            switch self {
            case .unsupportedKey: return "请选择字母、数字或 F1–F12 键。"
            case .unsupportedModifiers: return "仅支持 ⌘、⇧、⌥ 和 ⌃ 修饰键。"
            case .insufficientModifiers: return "请至少选择两个修饰键，其中包含 ⌘ 或 ⌃，避免影响普通输入。"
            case .reservedShortcut: return "这个组合用于编辑、退出或 macOS 系统功能，请换一个快捷键。"
            }
        }
    }
}

/// One versioned value prevents half-written shortcut/retention combinations.
/// Invalid/future payloads are ignored without silently overwriting them.
final class AppPreferences {
    static let storageKey = "AprilShot.preferences"
    static let supportedRetentionDays = [1, 3, 7, 30, 0]
    private static let schemaVersion = 1
    private let defaults: UserDefaults
    private var stored: StoredPreferences
    private(set) var loadWarning: String?

    private struct StoredPreferences: Codable {
        var version: Int
        var shortcut: HotKeyShortcut
        var retentionDays: Int
        // Optional so version-1 payloads without this safeguard remain readable.
        var retentionNeedsReview: Bool? = nil
    }

    private static let unreadableWarning = "无法读取已保存的设置，已使用默认快捷键 ⌘⇧2。自动清理已暂停，请在“设置…”中确认保留时间并保存。"
    private static let reviewWarning = "自动清理已暂停，请在“设置…”中确认图片保留时间并保存。"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = StoredPreferences(version: Self.schemaVersion, shortcut: .defaultShortcut, retentionDays: 3)
        guard let value = defaults.object(forKey: Self.storageKey) else { return }
        guard let data = value as? Data,
              let decoded = try? JSONDecoder().decode(StoredPreferences.self, from: data),
              decoded.version == Self.schemaVersion,
              Self.supportedRetentionDays.contains(decoded.retentionDays) else {
            stored.retentionNeedsReview = true
            loadWarning = Self.unreadableWarning
            return
        }
        stored = decoded
        if decoded.retentionNeedsReview == true { loadWarning = Self.reviewWarning }
    }

    var shortcut: HotKeyShortcut { stored.shortcut }
    /// Zero means never delete automatically. Invalid values leave it unchanged.
    var retentionDays: Int {
        get { stored.retentionDays }
        set {
            guard Self.supportedRetentionDays.contains(newValue) else { return }
            stored.retentionDays = newValue
            stored.retentionNeedsReview = nil
            persist()
        }
    }
    func saveShortcut(_ shortcut: HotKeyShortcut) {
        stored.shortcut = shortcut
        persist()
    }
    /// Validate first, then write all settings as one UserDefaults value.
    func save(shortcut: HotKeyShortcut, retentionDays: Int) throws {
        guard Self.supportedRetentionDays.contains(retentionDays) else { throw PreferenceError.invalidRetention }
        stored = StoredPreferences(version: Self.schemaVersion, shortcut: shortcut, retentionDays: retentionDays)
        persist()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.storageKey)
        loadWarning = stored.retentionNeedsReview == true ? Self.reviewWarning : nil
    }
    enum PreferenceError: LocalizedError {
        case invalidRetention
        var errorDescription: String? { "请选择保留 1、3、7、30 天或永不自动清理。" }
    }
}
