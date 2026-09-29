import Carbon.HIToolbox
import WheedgetsCore
import OSLog

/// The on/off shortcut, registered with Carbon's `RegisterEventHotKey`.
///
/// Unlike an event tap this needs no permission and never sees other
/// keystrokes, so the app watches nothing while drums are off.
@MainActor
final class GlobalHotkey {
    nonisolated static let signature: OSType = 0x4B44_524D // "KDRM"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            Logger.input.error("InstallEventHandler failed: \(status)")
        }
    }

    /// Returns false when the combination is taken by another app or invalid.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            hotkey.modifiers.rawValue,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            Logger.input.error("RegisterEventHotKey failed: \(status)")
            hotKeyRef = nil
            return false
        }
        return true
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    fileprivate func fire() {
        action()
    }
}

/// Carbon delivers application events on the main thread.
private func hotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr, id.signature == GlobalHotkey.signature else { return OSStatus(eventNotHandledErr) }
    let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotkey.fire() }
    return noErr
}
