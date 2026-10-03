import AppKit
import Carbon

/// An injectable boundary: tests exercise conflicts without reserving OS keys.
protocol HotKeyRegistering: AnyObject {
    func installHandler(_ onPress: @escaping (UInt32) -> Void) throws
    func register(_ shortcut: HotKeyShortcut, id: UInt32) throws
    func unregister(id: UInt32) throws
    func removeHandler()
}

/// Carbon's registered hotkey avoids a global event tap/Accessibility permission.
final class HotKeyManager {
    private let registry: HotKeyRegistering
    private var handlerInstalled = false
    private var activeID: UInt32?
    private var nextID: UInt32 = 1
    private(set) var activeShortcut: HotKeyShortcut?
    var onPress: (() -> Void)?

    init(registry: HotKeyRegistering = CarbonHotKeyRegistry()) { self.registry = registry }

    /// Acquire the candidate first: a conflict never drops the working shortcut.
    func register(_ shortcut: HotKeyShortcut = .defaultShortcut) throws {
        guard activeShortcut != shortcut else { return }
        if !handlerInstalled {
            try registry.installHandler { [weak self] identifier in
                guard let self = self, self.activeID == identifier else { return }
                self.onPress?()
            }
            handlerInstalled = true
        }
        let candidateID = nextID
        nextID &+= 1
        if nextID == 0 { nextID = 1 }
        do { try registry.register(shortcut, id: candidateID) }
        catch { throw HotKeyError(shortcut: shortcut, underlying: error) }
        if let previousID = activeID {
            do { try registry.unregister(id: previousID) }
            catch {
                // If release fails, keep routing the previous ID. The backend
                // retains any failed-to-release token for teardown/retry.
                try? registry.unregister(id: candidateID)
                throw HotKeyError(shortcut: shortcut, underlying: error)
            }
        }
        activeID = candidateID
        activeShortcut = shortcut
    }

    func applyShortcut(_ shortcut: HotKeyShortcut, preferences: AppPreferences) throws {
        try register(shortcut)
        preferences.saveShortcut(shortcut)
    }

    /// Return a warning for the caller to present; menu/UI must use activeShortcut
    /// rather than claiming a saved-but-conflicting preference is working.
    @discardableResult
    func registerSavedShortcut(from preferences: AppPreferences) -> String? {
        let saved = preferences.shortcut
        do {
            try register(saved)
            return preferences.loadWarning
        } catch {
            let failure = error.localizedDescription
            if saved != .defaultShortcut {
                do {
                    try register(.defaultShortcut)
                    return "\(failure)\n本次已改用默认快捷键 \(HotKeyShortcut.defaultShortcut.displayString)。原设置仍保留，可在“设置…”中修改。"
                } catch {
                    return "\(failure)\n默认快捷键也无法启用。请从菜单栏点击“截图”，并在“设置…”中选择其他组合。"
                }
            }
            return "\(failure)\n请从菜单栏点击“截图”，并在“设置…”中选择其他组合。"
        }
    }

    deinit {
        if let activeID = activeID { try? registry.unregister(id: activeID) }
        registry.removeHandler()
    }

    struct HotKeyError: LocalizedError {
        let shortcut: HotKeyShortcut
        let underlying: Error
        var errorDescription: String? {
            "\(shortcut.displayString) 注册失败，可能与其他应用冲突（\(underlying.localizedDescription)）。"
        }
    }
}

final class CarbonHotKeyRegistry: HotKeyRegistering {
    private static let signature: OSType = 0x534E4150 // SNAP
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var onPress: ((UInt32) -> Void)?

    func installHandler(_ onPress: @escaping (UInt32) -> Void) throws {
        if handler != nil { self.onPress = onPress; return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == CarbonHotKeyRegistry.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let registry = Unmanaged<CarbonHotKeyRegistry>.fromOpaque(context).takeUnretainedValue()
            let id = identifier.id
            guard registry.hotKeys[id] != nil else { return OSStatus(eventNotHandledErr) }
            // Read activeID only when delivered, so a queued old-key event
            // cannot fire the capture after the user changes their shortcut.
            DispatchQueue.main.async { [weak registry] in registry?.onPress?(id) }
            return noErr
        }, 1, &event, context, &handler)
        guard status == noErr else { handler = nil; throw RegistryError(status: status) }
        self.onPress = onPress
    }

    func register(_ shortcut: HotKeyShortcut, id: UInt32) throws {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: id)
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers.rawValue,
                                         identifier, GetApplicationEventTarget(), 0, &reference)
        guard result == noErr, let reference = reference else {
            throw RegistryError(status: result == noErr ? OSStatus(paramErr) : result)
        }
        hotKeys[id] = reference
    }

    func unregister(id: UInt32) throws {
        guard let reference = hotKeys[id] else { return }
        let result = UnregisterEventHotKey(reference)
        guard result == noErr else { throw RegistryError(status: result) }
        hotKeys.removeValue(forKey: id)
    }

    func removeHandler() {
        onPress = nil
        if let handler = handler { RemoveEventHandler(handler) }
        handler = nil
        // Also release candidates left over after a rare unregister failure.
        for reference in hotKeys.values { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
    }
    deinit { removeHandler() }

    struct RegistryError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "系统错误 \(status)" }
    }
}
