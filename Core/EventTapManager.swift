import CoreGraphics
import AppKit

@MainActor
final class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isTapActive: Bool = false

    /// Set by OverlayCompletionManager when a suggestion is visible.
    var isSuggestionVisible: Bool = false

    var onTabPressed: ((pid_t?) -> Bool)?
    var onEscapePressed: (() -> Void)?
    var onManualTriggerPressed: ((pid_t?) -> Bool)?
    var onPaletteCycleRequested: ((Int, pid_t?) -> Bool)?
    var onSuggestionNumberPressed: ((Int, pid_t?) -> Bool)?
    var onTapStatusChanged: ((Bool) -> Void)?

    var manualTriggerEnabled: Bool = false
    var manualTriggerKeyCode: Int64 = 49
    var manualTriggerModifiers: CGEventFlags = [.maskAlternate]
    var paletteNextKeyCode: Int64 = 125
    var paletteNextModifiers: CGEventFlags = [.maskAlternate]
    var palettePreviousKeyCode: Int64 = 126
    var palettePreviousModifiers: CGEventFlags = [.maskAlternate]

    // MARK: - Lifecycle

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallbackFunction,
            userInfo: refcon
        ) else {
            isTapActive = false
            onTapStatusChanged?(false)
            NSLog(
                "[AIComplete] Event tap creation failed (global hotkeys unavailable). AXTrusted=\(AXIsProcessTrusted()) InputMonitoring=\(CGPreflightListenEventAccess())"
            )
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isTapActive = true
        onTapStatusChanged?(true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isTapActive = false
        onTapStatusChanged?(false)
    }

    deinit {
        // Note: stop() can't be called from deinit on @MainActor,
        // but the fields will be cleaned up automatically.
    }

    // MARK: - Event Handling (called synchronously from the tap callback on main thread)

    fileprivate func handleKeyEvent(_ event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let targetPID = targetProcessID(from: event)
        let normalizedFlags = normalizedModifierFlags(event.flags)

        // Tab = keyCode 48
        if keyCode == 48 && isSuggestionVisible {
            let consumed = onTabPressed?(targetPID) ?? false
            return consumed ? nil : event
        }

        // Escape = keyCode 53
        if keyCode == 53 && isSuggestionVisible {
            onEscapePressed?()
            return nil // consume
        }

        if isSuggestionVisible,
           let suggestionIndex = suggestionIndexShortcut(for: keyCode, modifiers: normalizedFlags) {
            let consumed = onSuggestionNumberPressed?(suggestionIndex, targetPID) ?? false
            return consumed ? nil : event
        }

        if isSuggestionVisible,
           matchesHotkey(keyCode: keyCode, modifiers: normalizedFlags, expectedKeyCode: paletteNextKeyCode, expectedModifiers: paletteNextModifiers) {
            let consumed = onPaletteCycleRequested?(1, targetPID) ?? false
            return consumed ? nil : event
        }

        if isSuggestionVisible,
           matchesHotkey(keyCode: keyCode, modifiers: normalizedFlags, expectedKeyCode: palettePreviousKeyCode, expectedModifiers: palettePreviousModifiers) {
            let consumed = onPaletteCycleRequested?(-1, targetPID) ?? false
            return consumed ? nil : event
        }

        if manualTriggerEnabled,
           matchesHotkey(keyCode: keyCode, modifiers: normalizedFlags, expectedKeyCode: manualTriggerKeyCode, expectedModifiers: manualTriggerModifiers) {
            if isSuggestionVisible {
                let consumed = onPaletteCycleRequested?(1, targetPID) ?? false
                return consumed ? nil : event
            }

            let consumed = onManualTriggerPressed?(targetPID) ?? false
            return consumed ? nil : event
        }

        return event // pass through
    }

    private func targetProcessID(from event: CGEvent) -> pid_t? {
        let rawPID = event.getIntegerValueField(.eventTargetUnixProcessID)
        guard rawPID > 0 else { return nil }
        return pid_t(rawPID)
    }

    private func normalizedModifierFlags(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
    }

    private func matchesHotkey(
        keyCode: Int64,
        modifiers: CGEventFlags,
        expectedKeyCode: Int64,
        expectedModifiers: CGEventFlags
    ) -> Bool {
        keyCode == expectedKeyCode && modifiers == normalizedModifierFlags(expectedModifiers)
    }

    private func suggestionIndexShortcut(for keyCode: Int64, modifiers: CGEventFlags) -> Int? {
        guard modifiers.isEmpty else { return nil }
        switch keyCode {
        case 18: return 0
        case 19: return 1
        case 20: return 2
        default: return nil
        }
    }

    /// Re-enable the tap if the system temporarily disabled it.
    fileprivate func reenableTapIfNeeded() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

// MARK: - C callback (must be a free function)

private func eventTapCallbackFunction(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Handle system-disabled tap events
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon {
            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            // Callback runs on main run loop — safe to assume MainActor
            MainActor.assumeIsolated {
                manager.reenableTapIfNeeded()
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown, let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()

    // The callback runs on the main thread (because we added the source to CFRunLoopGetMain).
    // EventTapManager is @MainActor, so this access is safe.
    var result: CGEvent?
    MainActor.assumeIsolated {
        result = manager.handleKeyEvent(event)
    }
    if let result {
        return Unmanaged.passUnretained(result)
    }
    return nil // event consumed
}
