import Carbon.HIToolbox

/// Global shortcut definitions, in one place so the UI can display exactly what's
/// registered instead of hard-coding a string that drifts out of sync.
enum Shortcuts {

    // MARK: - Forage toggle

    /// ⌃⌥⌘F.
    ///
    /// Deliberately *not* ⌘⇧F. `RegisterEventHotKey` claims a combination system-wide,
    /// so ⌘⇧F would swallow "Find in Files" in VS Code / Cursor and every other editor —
    /// a daily-driver shortcut for anyone writing code. This combination is mnemonic
    /// (F for Forage) and effectively never bound by anything else.
    static let forageKeyCode = UInt32(kVK_ANSI_F)
    static let forageModifiers = UInt32(controlKey | optionKey | cmdKey)
    static let forageDisplay = "⌃⌥⌘F"

    // MARK: - Picker

    static let pickerDisplay = "⌘⇧V"
}
