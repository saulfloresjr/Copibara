import AppKit
import Carbon.HIToolbox

/// Global hotkeys that work even when the app is in the background.
///
/// One Carbon handler dispatches every hotkey by ID. The earlier design installed a
/// separate handler per hotkey, which only worked as long as each handler correctly
/// declined events that weren't its own and Carbon walked the whole chain — two
/// assumptions that are easy to get subtly wrong and hard to observe when they fail.
/// A single handler with a dictionary has neither problem.
final class HotkeyCenter {

    static let shared = HotkeyCenter()

    /// Stable IDs so registrations can be reasoned about and replaced.
    enum ID: UInt32 {
        case picker = 1
        case forage = 2
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    private init() {}

    /// Register a global hotkey. Returns false if the system refused it — usually
    /// because another app already owns that combination.
    @discardableResult
    func register(
        _ id: ID,
        keycode: UInt32,
        modifiers: UInt32,
        handler: @escaping () -> Void
    ) -> Bool {
        installHandlerIfNeeded()
        unregister(id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("CBPK"), id: id.rawValue)
        let status = RegisterEventHotKey(
            keycode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )

        guard status == noErr, let ref else {
            print("[Hotkey] ❌ \(id) failed to register (OSStatus \(status))")
            return false
        }
        refs[id.rawValue] = ref
        handlers[id.rawValue] = handler
        print("[Hotkey] ✅ \(id) registered")
        return true
    }

    func unregister(_ id: ID) {
        if let ref = refs[id.rawValue] {
            UnregisterEventHotKey(ref)
            refs[id.rawValue] = nil
        }
        handlers[id.rawValue] = nil
    }

    fileprivate func fire(_ rawID: UInt32) {
        guard let handler = handlers[rawID] else { return }
        DispatchQueue.main.async(execute: handler)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()

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
                guard status == noErr else { return OSStatus(eventNotHandledErr) }

                center.fire(firedID.id)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
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
