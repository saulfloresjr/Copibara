import AppKit
import Carbon.HIToolbox

/// Global shortcut definitions, in one place so the UI can display exactly what's
/// registered instead of hard-coding a string that drifts out of sync.
enum Shortcuts {

    // MARK: - Forage toggle — ⌘⇧F

    /// Two modifiers, mnemonic, easy one-handed.
    ///
    /// ⌘⇧F is unused by macOS itself (verified against com.apple.symbolichotkeys),
    /// but editors bind it to Find-in-Files. A Carbon hotkey claims a chord
    /// system-wide and would swallow it there, so this one is handled through the
    /// event tap instead and *yields* to the apps that own it — see
    /// `ownsForageChord(frontmostApp:)`. That way the shortcut stays two keys
    /// everywhere it matters without breaking anything.
    static let forageKeyCode: Int64 = Int64(kVK_ANSI_F)
    static let forageDisplay = "⌘⇧F"

    /// Modifiers that must be held.
    static let forageRequiredFlags: CGEventFlags = [.maskCommand, .maskShift]
    /// Modifiers that must NOT be held, so ⌃⌘⇧F / ⌥⌘⇧F still reach the app.
    static let forageForbiddenFlags: CGEventFlags = [.maskAlternate, .maskControl]

    /// Apps for which ⌘⇧F belongs to them, not to us.
    private static let chordOwners: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium.codium",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.exafunction.windsurf",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "dev.zed.Zed",
        "com.panic.Nova",
        "com.github.atom",
    ]

    /// True when the frontmost app owns ⌘⇧F and we should pass the keystroke through.
    static func ownsForageChord() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        if chordOwners.contains(bundleID) { return true }
        // JetBrains ships a family of IDEs that all bind Find-in-Files.
        return bundleID.hasPrefix("com.jetbrains.")
    }

    // MARK: - Picker

    static let pickerDisplay = "⌘⇧V"
}
