import AppKit
import Carbon

/// Carbon's registered hotkey avoids a global key event tap and Accessibility permission.
final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    func register() throws {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x534E4150, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { manager.onPress?() }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { throw HotKeyError(status: installed) }
        let identifier = EventHotKeyID(signature: 0x534E4150, id: 1) // SNAP
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey),
                                         identifier, GetApplicationEventTarget(), 0, &hotKey)
        guard result == noErr else {
            if let handler = handler { RemoveEventHandler(handler) }
            handler = nil
            throw HotKeyError(status: result)
        }
    }
    deinit {
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
        if let handler = handler { RemoveEventHandler(handler) }
    }
    struct HotKeyError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "无法注册 ⌘⇧2（错误 \(status)）。可能与其他 App 的快捷键冲突。你仍可使用菜单栏的“截取区域”。"
        }
    }
}
