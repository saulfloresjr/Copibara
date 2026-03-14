import AppKit
import Carbon.HIToolbox

/// Zero-delay screenshot capture via the tilde/backtick key (keyCode 50).
///
/// **Design**: Crosshair appears INSTANTLY on keyDown. If the user releases quickly
/// (< 150ms), it was a typing intent — crosshair is cancelled and a backtick is re-injected.
/// If the user holds longer, the crosshair stays for drag-to-capture. On keyUp, the
/// crosshair is cancelled (Escape) unless the user already captured a screenshot.
///
/// This "assume screenshot, fallback to typing" approach eliminates all perceivable delay.
///
/// Uses CGEventTap for global input monitoring. Requires Accessibility permissions.
final class TildeScreenshotService {

    // MARK: - Configuration

    /// If the key is released within this window, treat it as a backtick tap (not a screenshot).
    /// 150ms is fast enough that the crosshair flash is nearly imperceptible for typing.
    private let tapThreshold: TimeInterval = 0.15

    /// The keyCode for the grave accent / tilde key
    private let tildeKeyCode: Int64 = 50  // kVK_ANSI_Grave

    /// Sentinel value stamped onto re-injected events so the tap ignores them
    private let reinjectedSentinel: Int64 = 0x434F5049  // "COPI" in ASCII

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyIsDown = false
    private var screenshotFired = false
    private var keyDownTime: UInt64 = 0  // mach_absolute_time for sub-ms precision
    private var clipboardChangeCount: Int = 0  // pasteboard changeCount at keyDown

    // MARK: - Lifecycle

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let service = Unmanaged<TildeScreenshotService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ TildeScreenshotService: Failed to create event tap. Check Accessibility permissions.")
            return
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("✅ TildeScreenshotService: Started — press ~ for instant screenshot capture")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        keyIsDown = false
        screenshotFired = false

        print("🛑 TildeScreenshotService: Stopped")
    }

    deinit {
        stop()
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        guard keyCode == tildeKeyCode else {
            return Unmanaged.passRetained(event)
        }

        // Pass through events we re-injected ourselves (avoids infinite loop)
        if event.getIntegerValueField(.eventSourceUserData) == reinjectedSentinel {
            return Unmanaged.passRetained(event)
        }

        // Ignore if any modifiers are held (Shift+`, Cmd+`, etc.)
        let flags = event.flags
        let modifierFlags: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl]
        if !flags.intersection(modifierFlags).isEmpty {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event: event)
        case .keyUp:
            return handleKeyUp(event: event)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Ignore key-repeat events
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            if keyIsDown { return nil }  // swallow repeats during screenshot mode
            return Unmanaged.passRetained(event)
        }

        // ── INSTANT TRIGGER ──
        // Fire the crosshair NOW, on the very first keyDown. Zero delay.
        keyIsDown = true
        screenshotFired = true
        keyDownTime = mach_absolute_time()
        clipboardChangeCount = NSPasteboard.general.changeCount
        triggerScreenshot()

        // Swallow the keyDown — we'll handle everything on keyUp
        return nil
    }

    private func handleKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard keyIsDown else {
            return Unmanaged.passRetained(event)
        }

        keyIsDown = false

        // Calculate how long the key was held (in seconds)
        let elapsed = machTimeToSeconds(mach_absolute_time() - keyDownTime)

        if elapsed < tapThreshold {
            // ── SHORT TAP ── User was typing a backtick, not taking a screenshot.
            // Cancel the crosshair and re-inject the backtick character.
            cancelScreenshot()
            reinjectBacktick()
            screenshotFired = false
            print("⌨️ TildeScreenshotService: Quick tap (\(Int(elapsed * 1000))ms) — backtick re-injected")
        } else {
            // ── HELD ── User was in screenshot mode.
            // Check if a screenshot already landed on the clipboard.
            // Two-stage check: immediate → 80ms fallback (for in-flight captures).
            let savedChangeCount = clipboardChangeCount
            screenshotFired = false

            let currentCount = NSPasteboard.general.changeCount
            if currentCount != savedChangeCount {
                // Already captured — nothing to cancel
                print("📸 TildeScreenshotService: Screenshot captured (immediate detect)")
            } else {
                // Not yet — give macOS 80ms to finish an in-flight capture
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    guard let self = self else { return }
                    if NSPasteboard.general.changeCount != savedChangeCount {
                        print("📸 TildeScreenshotService: Screenshot captured (delayed detect)")
                    } else {
                        self.cancelScreenshot()
                        print("📸 TildeScreenshotService: No capture — crosshair dismissed")
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Actions

    /// Simulate ⌘⇧⌃4 INSTANTLY to trigger macOS interactive screenshot-to-clipboard.
    /// The Control modifier copies to clipboard instead of saving to file.
    private func triggerScreenshot() {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x15, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x15, keyDown: false) else { return }

        keyDown.flags = [.maskCommand, .maskShift, .maskControl]
        keyUp.flags = [.maskCommand, .maskShift, .maskControl]

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        print("📸 TildeScreenshotService: Crosshair activated instantly")
    }

    /// Cancel the screenshot crosshair by simulating Escape.
    private func cancelScreenshot() {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x35, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x35, keyDown: false) else { return }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Re-inject a backtick character for quick taps so normal typing works.
    private func reinjectBacktick() {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x32, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x32, keyDown: false) else { return }

        keyDown.setIntegerValueField(.eventSourceUserData, value: reinjectedSentinel)
        keyUp.setIntegerValueField(.eventSourceUserData, value: reinjectedSentinel)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Timing

    /// Convert mach_absolute_time delta to seconds with nanosecond precision.
    private func machTimeToSeconds(_ elapsed: UInt64) -> TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanoseconds = elapsed * UInt64(info.numer) / UInt64(info.denom)
        return TimeInterval(nanoseconds) / 1_000_000_000
    }
}
