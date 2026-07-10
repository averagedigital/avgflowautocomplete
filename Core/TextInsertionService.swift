import ApplicationServices
import AppKit

final class TextInsertionService {

    /// Primary: insert text via the Accessibility API by setting kAXSelectedTextAttribute.
    /// Returns `true` if successful.
    @discardableResult
    func insertViaAccessibility(
        text: String,
        into element: AXUIElement,
        replacementLength: Int = 0
    ) -> Bool {
        if replacementLength > 0 {
            return replaceViaAccessibility(text: text, into: element, replacementLength: replacementLength)
        }

        // Simple insertion at cursor position
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    /// Fallback: insert text via clipboard + Cmd+V.
    /// Preserves previous clipboard contents. Returns whether the paste event was posted,
    /// not whether the target app accepted the paste.
    @discardableResult
    func insertViaClipboard(text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?
            .compactMap { $0.copy() as? NSPasteboardItem } ?? []

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            pasteboard.clearContents()
            if !previousItems.isEmpty {
                _ = pasteboard.writeObjects(previousItems)
            }
            return false
        }
        let injectedChangeCount = pasteboard.changeCount

        let restoreClipboardIfUnchanged = {
            guard Self.shouldRestoreClipboard(
                injectedChangeCount: injectedChangeCount,
                currentChangeCount: pasteboard.changeCount
            ) else {
                return
            }
            pasteboard.clearContents()
            if !previousItems.isEmpty {
                _ = pasteboard.writeObjects(previousItems)
            }
        }

        // Synthesize Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: UInt16 = 0x09

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            restoreClipboardIfUnchanged()
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        // Restore clipboard after a short delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restoreClipboardIfUnchanged()
        }
        return true
    }

    static func shouldRestoreClipboard(
        injectedChangeCount: Int,
        currentChangeCount: Int
    ) -> Bool {
        injectedChangeCount == currentChangeCount
    }

    /// Replace an exact pre-captured selected range with new text.
    /// Useful for cross-app rewrite flows where we need deterministic range replacement.
    @discardableResult
    func replaceSelectedRangeViaAccessibility(
        text: String,
        in element: AXUIElement,
        selectedRange: CFRange
    ) -> Bool {
        guard setSelectedRange(element, selectedRange: selectedRange) else {
            return false
        }

        let replaceResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return replaceResult == .success
    }

    // MARK: - Private

    private func replaceViaAccessibility(text: String, into element: AXUIElement, replacementLength: Int) -> Bool {
        // Read current cursor position
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success else {
            return false
        }

        guard let selectedRangeValue = axValue(from: rangeRef) else {
            return false
        }

        var currentRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(selectedRangeValue, .cfRange, &currentRange) else {
            return false
        }

        // Expand selection backwards by replacementLength UTF-16 code units.
        var replaceRange = Self.replacementRange(
            cursorRange: currentRange,
            replacementUTF16Length: replacementLength
        )

        guard let axRange = AXValueCreate(.cfRange, &replaceRange) else {
            return false
        }

        // Set the selection to the range we want to replace
        let selectResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        guard selectResult == .success else {
            return false
        }

        // Replace selected text
        let insertResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard insertResult == .success else {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                selectedRangeValue
            )
            return false
        }
        return true
    }

    static func replacementRange(
        cursorRange: CFRange,
        replacementUTF16Length: Int
    ) -> CFRange {
        let cursorLocation = max(0, cursorRange.location)
        let replaceStart = max(0, cursorLocation - max(0, replacementUTF16Length))
        return CFRange(location: replaceStart, length: cursorLocation - replaceStart)
    }

    private func axValue(from reference: CFTypeRef?) -> AXValue? {
        guard let reference else { return nil }
        guard CFGetTypeID(reference) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(reference, to: AXValue.self)
    }

    @discardableResult
    func setSelectedRange(_ element: AXUIElement, selectedRange: CFRange) -> Bool {
        var safeRange = CFRange(location: max(0, selectedRange.location), length: max(0, selectedRange.length))
        guard let rangeAXValue = AXValueCreate(.cfRange, &safeRange) else {
            return false
        }
        let selectResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeAXValue
        )
        return selectResult == .success
    }
}
