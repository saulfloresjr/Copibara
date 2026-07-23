import AppKit
import Carbon.HIToolbox

/// Long-press screenshot via the tilde/backtick key (keyCode 50).
///
/// **Behavior**:
/// - **Quick tap** (< 50ms): Types a backtick character.
/// - **Long press** (≥ 50ms): Crosshair appears while held. Drag to select area.
///   - **Release after drag-capture**: Screenshot saved to clipboard.
///   - **Release without capturing**: Crosshair dismissed, cursor returns to normal.
///
/// Uses CGEventTap. Requires Accessibility permissions.
final class TildeScreenshotService {

    // MARK: - Configuration

    /// Tap threshold — releases faster than this produce a backtick.
    /// 50ms is tuned for fast users who want the crosshair to engage near-instantly.
    /// Lower = snappier (risk: fast `~` taps trigger the crosshair); raise if that bites.
    private let tapThreshold: TimeInterval = 0.05  // 50ms

    private let tildeKeyCode: Int64 = 50  // kVK_ANSI_Grave
    private let reinjectedSentinel: Int64 = 0x434F5049  // "COPI"

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyIsDown = false
    private var keyDownTime: UInt64 = 0
    private var crosshairLaunched = false
    private var clipboardChangeCount: Int = 0
    private var crosshairWorkItem: DispatchWorkItem?

    // MARK: - Lifecycle

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

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
            print("⚠️ TildeScreenshotService: Failed to create event tap.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("✅ TildeScreenshotService: Started — hold ~ for screenshot, tap ~ for backtick")
    }

    func stop() {
        crosshairWorkItem?.cancel()
        crosshairWorkItem = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        keyIsDown = false
        crosshairLaunched = false
        print("🛑 TildeScreenshotService: Stopped")
    }

    deinit { stop() }

    // MARK: - Event Routing

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == tildeKeyCode else { return Unmanaged.passRetained(event) }

        if event.getIntegerValueField(.eventSourceUserData) == reinjectedSentinel {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let modifierFlags: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl]
        if !flags.intersection(modifierFlags).isEmpty {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown: return handleKeyDown(event: event)
        case .keyUp:   return handleKeyUp(event: event)
        default:       return Unmanaged.passRetained(event)
        }
    }

    // MARK: - Key Down

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            if keyIsDown { return nil }
            return Unmanaged.passRetained(event)
        }

        keyIsDown = true
        crosshairLaunched = false
        keyDownTime = mach_absolute_time()
        clipboardChangeCount = NSPasteboard.general.changeCount

        // Snapshot the source *now*, while the page you're looking at is still
        // frontmost — once the crosshair takes over, that context is gone. Deferred
        // to the next main-loop tick so the AX reads never sit on the keystroke path
        // and can't jeopardise the 50ms tap threshold. No-ops unless Forage is armed.
        DispatchQueue.main.async {
            ForageMode.shared.latchContext()
        }

        // Schedule crosshair after tap threshold — cancelled if released early
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.keyIsDown, !self.crosshairLaunched else { return }
            self.crosshairLaunched = true
            self.launchCrosshair()
        }
        crosshairWorkItem?.cancel()
        crosshairWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + tapThreshold, execute: workItem)

        return nil  // swallow
    }

    // MARK: - Key Up

    private func handleKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard keyIsDown else { return Unmanaged.passRetained(event) }
        keyIsDown = false

        let elapsed = machTimeToSeconds(mach_absolute_time() - keyDownTime)

        if !crosshairLaunched {
            // ── QUICK TAP — crosshair never appeared ──
            crosshairWorkItem?.cancel()
            crosshairWorkItem = nil
            // No capture is coming, so drop the context we latched on key-down.
            DispatchQueue.main.async { ForageMode.shared.clearLatch() }
            reinjectBacktick()
            print("⌨️ Tilde: tap (\(Int(elapsed * 1000))ms) → backtick")
            return nil
        }

        // ── LONG PRESS — crosshair was launched ──
        // Check if a screenshot was captured (pasteboard changed).
        // Give macOS 50ms to finalize the capture before checking.
        let savedCount = clipboardChangeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            if NSPasteboard.general.changeCount != savedCount {
                // User dragged-to-capture before releasing — screenshot saved
                print("📸 Tilde: screenshot captured")
            } else {
                // No capture — dismiss the crosshair (send Escape)
                self.dismissCrosshair()
                print("📸 Tilde: released — crosshair dismissed")
            }
        }

        crosshairLaunched = false
        return nil
    }

    // MARK: - Actions

    /// Fire ⌘⇧⌃4 to launch the macOS screenshot crosshair.
    private func launchCrosshair() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x15, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: 0x15, keyDown: false) else { return }

        down.flags = [.maskCommand, .maskShift, .maskControl]
        up.flags   = [.maskCommand, .maskShift, .maskControl]

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        print("📸 Tilde: crosshair ON")
    }

    /// Send Escape to dismiss the macOS screenshot crosshair.
    private func dismissCrosshair() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x35, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: 0x35, keyDown: false) else { return }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Re-inject a backtick character.
    private func reinjectBacktick() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x32, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: 0x32, keyDown: false) else { return }

        down.setIntegerValueField(.eventSourceUserData, value: reinjectedSentinel)
        up.setIntegerValueField(.eventSourceUserData, value: reinjectedSentinel)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Timing

    private func machTimeToSeconds(_ elapsed: UInt64) -> TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanoseconds = elapsed * UInt64(info.numer) / UInt64(info.denom)
        return TimeInterval(nanoseconds) / 1_000_000_000
    }
}
