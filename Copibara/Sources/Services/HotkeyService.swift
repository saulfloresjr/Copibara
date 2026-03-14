import AppKit
import Carbon.HIToolbox

/// Registers a global hotkey (⌘⇧V) that works even when the app is in the background.
final class HotkeyService {

    private var eventHotKey: EventHotKeyRef?
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func register() {
        // ⌘⇧V  (keycode 9 = V)
        let hotKeyID = EventHotKeyID(signature: fourCharCode("CBPK"), id: 1)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keycode: UInt32 = UInt32(kVK_ANSI_V)

        // Install handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerRef = Unmanaged.passRetained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    service.handler()
                }
                return noErr
            },
            1,
            &eventType,
            handlerRef,
            nil
        )

        RegisterEventHotKey(
            keycode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKey
        )
    }

    func unregister() {
        if let hotKey = eventHotKey {
            UnregisterEventHotKey(hotKey)
            eventHotKey = nil
        }
    }

    deinit {
        unregister()
    }
}

// Helper to create OSType from a 4-char string
private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | OSType(char)
    }
    return result
}
