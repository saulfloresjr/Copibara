import AppKit
import Carbon.HIToolbox

/// Registers a global hotkey that works even when the app is in the background.
///
/// Defaults to ⌘⇧V (the clip picker); pass a keycode/modifiers/id for others.
final class HotkeyService {

    private var eventHotKey: EventHotKeyRef?
    private let handler: () -> Void
    private let keycode: UInt32
    private let modifiers: UInt32
    private let hotKeyID: UInt32

    init(
        keycode: UInt32 = UInt32(kVK_ANSI_V),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        id: UInt32 = 1,
        handler: @escaping () -> Void
    ) {
        self.keycode = keycode
        self.modifiers = modifiers
        self.hotKeyID = id
        self.handler = handler
    }

    func register() {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("CBPK"), id: self.hotKeyID)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerRef = Unmanaged.passRetained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()

                // Every installed handler receives every hotkey press, so each one
                // must confirm the event is its own. Without this check, registering
                // a second hotkey makes both actions fire on either keystroke.
                var firedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &firedID
                )
                guard status == noErr, firedID.id == service.hotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }

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
