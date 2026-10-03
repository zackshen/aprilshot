import AppKit
import Carbon

/// Never installs a Carbon handler or registers a real global key.
private final class FakeHotKeyRegistry: HotKeyRegistering {
    enum Failure: LocalizedError {
        case conflict, install, release
        var errorDescription: String? {
            switch self {
            case .conflict: return "test conflict"
            case .install: return "test handler failure"
            case .release: return "test release failure"
            }
        }
    }
    var blocked: [HotKeyShortcut] = []
    var failInstall = false
    var failReleaseID: UInt32?
    var registrations: [UInt32: HotKeyShortcut] = [:]
    var operations: [String] = []
    var callback: ((UInt32) -> Void)?

    func installHandler(_ onPress: @escaping (UInt32) -> Void) throws {
        operations.append("install")
        if failInstall { throw Failure.install }
        callback = onPress
    }
    func register(_ shortcut: HotKeyShortcut, id: UInt32) throws {
        operations.append("register:\(id)")
        if blocked.contains(shortcut) { throw Failure.conflict }
        registrations[id] = shortcut
    }
    func unregister(id: UInt32) throws {
        operations.append("unregister:\(id)")
        if failReleaseID == id { throw Failure.release }
        registrations.removeValue(forKey: id)
    }
    func removeHandler() {
        operations.append("removeHandler")
        registrations.removeAll()
        callback = nil
    }
    func emit(_ id: UInt32) { callback?(id) }
}

@main
struct HotKeyPreferencesTests {
    static var checks = 0
    static var failures = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }
    static func rejects(_ message: String, _ body: () throws -> Void) {
        do { try body(); check(false, message) }
        catch { check(true, message) }
    }
    static func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "AprilShot.Tests.HotKeyPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    static func checkShortcutModel() throws {
        let standard = HotKeyShortcut.defaultShortcut
        check(standard.keyCode == 19 && standard.modifiers == [.command, .shift], "default is physical Command-Shift-2")
        check(standard.displayString == "⌘⇧2" && standard.keyEquivalent == "2", "default display/menu key are stable")
        check(standard.keyEquivalentModifierMask == [.command, .shift], "menu converts Carbon modifiers to AppKit flags")
        check(HotKeyShortcut.supportedKeys.count == 48, "supported keys include 26 letters, 10 digits, 12 function keys")
        check(Set(HotKeyShortcut.supportedKeys.map { $0.keyCode }).count == 48, "supported physical keys are unique")
        for key in HotKeyShortcut.supportedKeys {
            let value = try HotKeyShortcut(keyCode: key.keyCode, modifiers: [.control, .option])
            check(!value.keyEquivalent.isEmpty && value.displayString.hasSuffix(key.displayName), "\(key.displayName) has a menu key and display label")
            let decoded = try JSONDecoder().decode(HotKeyShortcut.self, from: JSONEncoder().encode(value))
            check(decoded == value, "\(key.displayName) preserves key and modifier bits through Codable")
        }
        let f12 = try HotKeyShortcut(keyCode: 111, modifiers: [.command, .option])
        check(f12.keyEquivalent == String(UnicodeScalar(NSF12FunctionKey)!), "F12 uses AppKit's native function-key equivalent")
        let invalidModifiers: [HotKeyModifiers] = [[], [.shift], [.option], [.command], [.control], [.shift, .option]]
        for modifiers in invalidModifiers {
            rejects("plain/typing/control modifiers rejected: \(modifiers.rawValue)") {
                _ = try HotKeyShortcut(keyCode: 19, modifiers: modifiers)
            }
        }
        rejects("unknown modifier bits rejected") {
            _ = try HotKeyShortcut(keyCode: 19, modifiers: HotKeyModifiers(rawValue: UInt32.max))
        }
        rejects("unsupported key rejected") { _ = try HotKeyShortcut(keyCode: 999, modifiers: [.command, .shift]) }
        let reservedKeys: [UInt32] = [0, 8, 9, 7, 6, 1, 12, 13, 4, 46, 20, 21, 23]
        for key in reservedKeys {
            rejects("reserved edit/system shortcut rejected for key \(key)") {
                _ = try HotKeyShortcut(keyCode: key, modifiers: [.command, .shift])
            }
        }
        for json in [
            #"{"keyCode":19,"modifiers":0}"#,
            #"{"keyCode":12,"modifiers":768}"#,
            #"{"keyCode":999,"modifiers":768}"#,
            #"{"keyCode":19,"modifiers":4294967295}"#,
            #"{"keyCode":-1,"modifiers":768}"#,
            #"{"keyCode":19}"#
        ] {
            rejects("decoding cannot bypass validation: \(json)") {
                _ = try JSONDecoder().decode(HotKeyShortcut.self, from: Data(json.utf8))
            }
        }
    }

    static func checkPreferences() throws {
        try withDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)
            check(preferences.shortcut == .defaultShortcut && preferences.retentionDays == 3, "first launch defaults to Command-Shift-2 and 3 days")
            check(preferences.loadWarning == nil, "first launch is not corruption")
            check(defaults.object(forKey: AppPreferences.storageKey) == nil, "reading defaults does not write a preference")
            let custom = try HotKeyShortcut(keyCode: 26, modifiers: [.control, .option])
            preferences.saveShortcut(custom)
            for days in AppPreferences.supportedRetentionDays {
                preferences.retentionDays = days
                let restored = AppPreferences(defaults: defaults)
                check(restored.shortcut == custom && restored.retentionDays == days, "shortcut and retention \(days) survive a new instance")
                check(restored.loadWarning == nil, "valid retention \(days) loads without a warning")
            }
            preferences.retentionDays = -1
            check(preferences.retentionDays == 0, "negative retention leaves Never unchanged")
            preferences.retentionDays = 2
            check(preferences.retentionDays == 0, "unsupported retention cannot silently shorten a policy")
            let data = defaults.data(forKey: AppPreferences.storageKey)!
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            check(json["version"] as? Int == 1, "persisted document has an explicit schema version")
            rejects("atomic save rejects invalid retention before any mutation") {
                try preferences.save(shortcut: .defaultShortcut, retentionDays: -1)
            }
            check(preferences.shortcut == custom && preferences.retentionDays == 0 &&
                  defaults.data(forKey: AppPreferences.storageKey) == data, "invalid full save preserves memory and persisted bytes")
            try preferences.save(shortcut: .defaultShortcut, retentionDays: 30)
            let fullySaved = AppPreferences(defaults: defaults)
            check(fullySaved.shortcut == .defaultShortcut && fullySaved.retentionDays == 30, "full save persists both choices together")
        }
        let corruptPayloads: [Any] = [
            "not a Data payload",
            Data("not JSON".utf8),
            Data(#"{}"#.utf8),
            Data(#"{"version":2,"shortcut":{"keyCode":19,"modifiers":768},"retentionDays":0}"#.utf8),
            Data(#"{"version":1,"shortcut":{"keyCode":999,"modifiers":768},"retentionDays":3}"#.utf8),
            Data(#"{"version":1,"shortcut":{"keyCode":19,"modifiers":0},"retentionDays":3}"#.utf8),
            Data(#"{"version":1,"shortcut":{"keyCode":19,"modifiers":768},"retentionDays":-1}"#.utf8),
            Data(#"{"version":1,"shortcut":{"keyCode":19,"modifiers":768},"retentionDays":365}"#.utf8)
        ]
        for corrupt in corruptPayloads {
            try withDefaults { defaults in
                defaults.set(corrupt, forKey: AppPreferences.storageKey)
                let preferences = AppPreferences(defaults: defaults)
                check(preferences.shortcut == .defaultShortcut && preferences.retentionDays == 3, "corrupt/unknown-version payload falls back to validated defaults")
                check(preferences.loadWarning != nil, "corruption exposes an honest launch warning")
                if let data = corrupt as? Data {
                    check(defaults.data(forKey: AppPreferences.storageKey) == data, "load does not overwrite an unreadable payload")
                }
                preferences.saveShortcut(.defaultShortcut)
                check(preferences.loadWarning != nil && AppPreferences(defaults: defaults).loadWarning != nil,
                      "shortcut-only save cannot resume cleanup after corruption, even after restart")
                preferences.retentionDays = 7
                check(preferences.loadWarning == nil && AppPreferences(defaults: defaults).retentionDays == 7, "explicit valid save repairs unreadable preferences")
            }
        }
    }

    static func checkRegistrationTransaction() throws {
        try withDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)
            let backend = FakeHotKeyRegistry()
            let manager = HotKeyManager(registry: backend)
            var presses = 0
            manager.onPress = { presses += 1 }
            try manager.applyShortcut(.defaultShortcut, preferences: preferences)
            check(backend.operations == ["install", "register:1"], "first registration installs exactly one handler")
            backend.emit(1)
            backend.emit(999)
            check(presses == 1, "only the active ID dispatches capture")
            try manager.applyShortcut(.defaultShortcut, preferences: preferences)
            check(backend.operations == ["install", "register:1"], "saving the same shortcut does not conflict with itself")
            let custom = try HotKeyShortcut(keyCode: 26, modifiers: [.control, .option])
            backend.blocked = [custom]
            let persistedBeforeFailure = defaults.data(forKey: AppPreferences.storageKey)
            rejects("a conflicting replacement reports failure") { try manager.applyShortcut(custom, preferences: preferences) }
            check(manager.activeShortcut == .defaultShortcut && preferences.shortcut == .defaultShortcut,
                  "conflict preserves active shortcut and preference")
            check(defaults.data(forKey: AppPreferences.storageKey) == persistedBeforeFailure, "conflict leaves persisted bytes untouched")
            check(backend.registrations == [1: .defaultShortcut] && !backend.operations.contains("unregister:1"),
                  "conflict never unregisters the working key")
            backend.emit(1)
            backend.emit(2)
            check(presses == 2, "old key still works and failed candidate does not")
            backend.blocked = []
            try manager.applyShortcut(custom, preferences: preferences)
            check(Array(backend.operations.suffix(2)) == ["register:3", "unregister:1"], "candidate acquired before prior key released, with a fresh ID")
            check(manager.activeShortcut == custom && preferences.shortcut == custom && backend.registrations == [3: custom], "successful replacement becomes the only active key and persists")
            check(AppPreferences(defaults: defaults).shortcut == custom, "replacement survives restart")
            backend.emit(1) // Simulate an event already queued before replacement.
            backend.emit(3)
            check(presses == 3, "stale old-key events are ignored after replacement")
        }
        try withDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)
            let backend = FakeHotKeyRegistry()
            let manager = HotKeyManager(registry: backend)
            try manager.applyShortcut(.defaultShortcut, preferences: preferences)
            backend.failReleaseID = 1
            let custom = try HotKeyShortcut(keyCode: 26, modifiers: [.control, .option])
            rejects("old-token release failure rejects replacement") { try manager.applyShortcut(custom, preferences: preferences) }
            check(manager.activeShortcut == .defaultShortcut && preferences.shortcut == .defaultShortcut && backend.registrations == [1: .defaultShortcut], "release failure rolls back candidate and retains old preference")
            check(Array(backend.operations.suffix(3)) == ["register:2", "unregister:1", "unregister:2"], "failed old release cleans the newly acquired token")
        }
        let backend = FakeHotKeyRegistry()
        do {
            let manager = HotKeyManager(registry: backend)
            backend.failInstall = true
            rejects("handler failure is surfaced") { try manager.register() }
            check(manager.activeShortcut == nil && backend.registrations.isEmpty, "failed handler creates no misleading active state")
            backend.failInstall = false
            try manager.register()
            check(backend.operations == ["install", "install", "register:1"], "failed handler installation can be retried")
        }
        check(backend.registrations.isEmpty && backend.callback == nil && Array(backend.operations.suffix(2)) == ["unregister:1", "removeHandler"], "teardown releases key and handler")
    }

    static func checkStartupFallback() throws {
        try withDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)
            let custom = try HotKeyShortcut(keyCode: 26, modifiers: [.control, .option])
            preferences.saveShortcut(custom)
            let backend = FakeHotKeyRegistry()
            backend.blocked = [custom]
            let manager = HotKeyManager(registry: backend)
            let warning = manager.registerSavedShortcut(from: preferences)
            check(warning?.contains("本次已改用默认快捷键") == true, "saved conflict reports actual successful fallback")
            check(manager.activeShortcut == .defaultShortcut && preferences.shortcut == custom, "fallback is active while saved choice remains available to repair")
            try manager.applyShortcut(.defaultShortcut, preferences: preferences)
            check(preferences.shortcut == .defaultShortcut && backend.operations.filter { $0.hasPrefix("register:") }.count == 2, "saving displayed fallback repairs preference without self-conflict")
        }
        try withDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)
            let custom = try HotKeyShortcut(keyCode: 26, modifiers: [.control, .option])
            preferences.saveShortcut(custom)
            let backend = FakeHotKeyRegistry()
            backend.blocked = [custom, .defaultShortcut]
            let manager = HotKeyManager(registry: backend)
            let warning = manager.registerSavedShortcut(from: preferences)
            check(warning?.contains("默认快捷键也无法启用") == true && manager.activeShortcut == nil, "double conflict never claims any global shortcut is active")
            check(preferences.shortcut == custom && backend.registrations.isEmpty, "double conflict does not destroy user's saved choice")
        }
        try withDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)
            let backend = FakeHotKeyRegistry()
            backend.blocked = [.defaultShortcut]
            let manager = HotKeyManager(registry: backend)
            let warning = manager.registerSavedShortcut(from: preferences)
            check(warning?.contains("菜单栏") == true && manager.activeShortcut == nil, "default launch conflict offers the menu action")
            check(backend.operations == ["install", "register:1"], "default conflict does not retry the same known-conflicting key")
            backend.blocked = []
            try manager.applyShortcut(.defaultShortcut, preferences: preferences)
            check(manager.activeShortcut == .defaultShortcut, "user can recover after a launch conflict")
        }
        try withDefaults { defaults in
            defaults.set(Data("corrupt".utf8), forKey: AppPreferences.storageKey)
            let preferences = AppPreferences(defaults: defaults)
            let manager = HotKeyManager(registry: FakeHotKeyRegistry())
            check(manager.registerSavedShortcut(from: preferences) == preferences.loadWarning, "successful default activation still reports damaged preferences")
            check(manager.activeShortcut == .defaultShortcut, "corrupt preferences activate only validated defaults")
            try preferences.save(shortcut: .defaultShortcut, retentionDays: 0)
            let restored = AppPreferences(defaults: defaults)
            check(restored.retentionDays == 0 && restored.loadWarning == nil,
                  "explicit full Save can repair corruption while keeping automatic cleanup disabled")
        }
    }

    static func main() throws {
        try checkShortcutModel()
        try checkPreferences()
        try checkRegistrationTransaction()
        try checkStartupFallback()
        print("HotKeyPreferencesTests: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
