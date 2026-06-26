import ApplicationServices
import AppKit

final class CursorPositionResolver {
    struct CursorAnchor {
        enum Quality {
            case preciseCaret
            case syntheticCaret
            case inputFallback

            var supportsInlineGhost: Bool {
                self == .preciseCaret
            }
        }

        let bounds: NSRect
        let quality: Quality
    }

    struct SyntheticTextPlacement: Equatable {
        let visualLineIndex: Int
        let column: Int
    }

    /// Get screen-space bounds of the text insertion point.
    /// AX coordinates are top-left origin; this returns bottom-left origin (NSRect).
    func cursorBounds(for element: AXUIElement) -> NSRect? {
        caretAnchor(for: element)?.bounds
    }

    /// Returns caret bounds with quality metadata.
    func caretAnchor(for element: AXUIElement) -> CursorAnchor? {
        let inputBounds = elementBounds(for: element)

        if let bounds = boundsForSelectedRange(element) {
            var flipped = flipToScreenCoordinates(bounds)
            if isReasonableCaretBounds(flipped, inside: inputBounds) {
                if flipped.width > 12 {
                    // Some AX providers return the full selected range bounds; collapse to caret-like width.
                    flipped = NSRect(
                        x: max(flipped.minX, flipped.maxX - 1),
                        y: flipped.minY,
                        width: 2,
                        height: max(16, min(32, flipped.height))
                    )
                }
                return CursorAnchor(bounds: flipped, quality: .preciseCaret)
            }
        }

        if let fallback = inputBounds {
            if let synthetic = syntheticCaretBounds(for: element, inside: fallback) {
                return CursorAnchor(bounds: synthetic, quality: .syntheticCaret)
            }

            let defaultFallback = NSRect(
                    x: fallback.minX + 8,
                    y: min(fallback.maxY - 26, max(fallback.minY + 4, fallback.midY - 10)),
                    width: 2,
                    height: max(16, min(24, fallback.height - 8))
                )
            return CursorAnchor(bounds: defaultFallback, quality: .inputFallback)
        }

        return nil
    }

    /// Get screen-space bounds of the full input element when available.
    func inputBounds(for element: AXUIElement) -> NSRect? {
        elementBounds(for: element)
    }

    /// Selected range length when available.
    func selectedRangeLength(for element: AXUIElement) -> Int {
        guard let selectedRange = selectedTextRange(for: element) else {
            return 0
        }
        return max(0, selectedRange.length)
    }

    // MARK: - Private

    private func selectedTextRange(for element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeValue = axValue(from: rangeRef) else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func boundsForSelectedRange(_ element: AXUIElement) -> CGRect? {
        guard let selectedRange = selectedTextRange(for: element) else {
            return nil
        }
        var range = selectedRange
        guard let selectedRangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        // Get bounds for that range
        var boundsRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &boundsRef
        )

        guard result == .success, let boundsValue = axValue(from: boundsRef) else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect) else {
            return nil
        }
        return rect
    }

    private func elementBounds(for element: AXUIElement) -> NSRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        guard let positionValue = axValue(from: posRef),
              let sizeValue = axValue(from: sizeRef) else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }

        let axRect = CGRect(origin: point, size: size)
        return flipToScreenCoordinates(axRect)
    }

    private func syntheticCaretBounds(for element: AXUIElement, inside inputBounds: NSRect) -> NSRect? {
        guard inputBounds.width > 20, inputBounds.height > 16 else {
            return nil
        }

        let selected = selectedTextRange(for: element)
        let role = stringAttribute(element, kAXRoleAttribute as String) ?? ""
        let isMultiline = role == (kAXTextAreaRole as String) || inputBounds.height >= 54
        guard let textSample = syntheticTextSample(for: element, selectedRange: selected) else {
            return nil
        }

        let lineHeight: CGFloat = min(26, max(18, inputBounds.height >= 54 ? 22 : 20))
        let leftInset: CGFloat = 8
        let topInset: CGFloat = 8
        let availableWidth = max(14, inputBounds.width - leftInset - 8)
        let maxLines = max(1, Int((inputBounds.height - topInset - 6) / lineHeight))

        var x = inputBounds.minX + leftInset + min(availableWidth * 0.35, 120)
        var y = inputBounds.midY - lineHeight * 0.5

        if isMultiline {
            let approxCharWidth: CGFloat = 8.6
            let charsPerLine = max(6, Int(availableWidth / approxCharWidth))
            let placement = Self.syntheticPlacement(
                prefix: textSample.prefix,
                charsPerLine: charsPerLine,
                maxLines: maxLines
            )

            x = inputBounds.minX + leftInset + min(availableWidth, CGFloat(max(0, placement.column)) * approxCharWidth)
            y = inputBounds.maxY - topInset - lineHeight * CGFloat(placement.visualLineIndex + 1)

            if y < inputBounds.minY + 4 {
                y = inputBounds.maxY - topInset - lineHeight
            }
        } else {
            if textSample.totalLength > 0 {
                let progress = CGFloat(textSample.caretLocation) / CGFloat(max(1, textSample.totalLength))
                x = inputBounds.minX + leftInset + progress * availableWidth
            } else if !textSample.prefix.isEmpty {
                x = inputBounds.minX + leftInset + min(availableWidth, CGFloat(textSample.prefix.count) * 8.6)
            }
            y = inputBounds.midY - lineHeight * 0.5
        }

        x = min(max(x, inputBounds.minX + 4), inputBounds.maxX - 4)
        y = min(max(y, inputBounds.minY + 2), inputBounds.maxY - lineHeight - 2)
        return NSRect(x: x, y: y, width: 2, height: lineHeight)
    }

    static func syntheticPlacement(
        prefix: String,
        charsPerLine: Int,
        maxLines: Int
    ) -> SyntheticTextPlacement {
        let safeCharsPerLine = max(1, charsPerLine)
        let safeMaxLines = max(1, maxLines)
        var visualLineIndex = 0
        var column = 0

        for character in prefix {
            if character == "\n" {
                visualLineIndex += 1
                column = 0
                continue
            }

            if column >= safeCharsPerLine {
                visualLineIndex += 1
                column = 0
            }

            column += 1
        }

        return SyntheticTextPlacement(
            visualLineIndex: min(visualLineIndex, safeMaxLines - 1),
            column: min(column, safeCharsPerLine)
        )
    }

    private struct SyntheticTextSample {
        let totalLength: Int
        let caretLocation: Int
        let prefix: String
    }

    private func syntheticTextSample(
        for element: AXUIElement,
        selectedRange: CFRange?
    ) -> SyntheticTextSample? {
        if let value = stringAttribute(element, kAXValueAttribute as String) {
            let nsValue = value as NSString
            let caretLocation: Int = {
                if let selectedRange {
                    return max(0, min(selectedRange.location, nsValue.length))
                }
                return nsValue.length
            }()
            return SyntheticTextSample(
                totalLength: nsValue.length,
                caretLocation: caretLocation,
                prefix: nsValue.substring(to: caretLocation)
            )
        }

        guard let selectedRange else {
            return nil
        }

        let caretLocation = max(0, selectedRange.location)
        let prefixStart = max(0, caretLocation - 4096)
        let prefixLength = max(0, caretLocation - prefixStart)
        let prefix = stringForRange(
            element,
            range: CFRange(location: prefixStart, length: prefixLength)
        ) ?? ""

        guard !prefix.isEmpty || caretLocation == 0 else {
            return nil
        }

        let totalLength = max(
            caretLocation,
            intAttribute(element, kAXNumberOfCharactersAttribute as String) ?? 0
        )

        return SyntheticTextSample(
            totalLength: totalLength,
            caretLocation: caretLocation,
            prefix: prefix
        )
    }

    private func isReasonableCaretBounds(_ bounds: NSRect, inside inputBounds: NSRect?) -> Bool {
        guard bounds.width > 0.5, bounds.height > 6 else {
            return false
        }

        if bounds.width > 180 || bounds.height > 120 {
            return false
        }

        if let inputBounds {
            guard bounds.intersects(inputBounds.insetBy(dx: -4, dy: -4)) else {
                return false
            }

            let inputArea = max(1, inputBounds.width * inputBounds.height)
            let boundsArea = bounds.width * bounds.height
            if boundsArea > inputArea * 0.34 {
                return false
            }

            if bounds.width > max(42, inputBounds.width * 0.28) {
                return false
            }
            if bounds.height > max(52, inputBounds.height * 0.82) {
                return false
            }
        }

        return true
    }

    /// Convert from AX top-left-origin coordinates to AppKit bottom-left-origin.
    private func flipToScreenCoordinates(_ axRect: CGRect) -> NSRect {
        // Find the screen containing the rect
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(CGPoint(x: axRect.midX, y: screen.frame.maxY - axRect.midY))
        } ?? NSScreen.main

        guard let screen else {
            return NSRect(origin: axRect.origin, size: axRect.size)
        }

        let flippedY = screen.frame.maxY - axRect.origin.y - axRect.size.height
        return NSRect(x: axRect.origin.x, y: flippedY, width: axRect.width, height: axRect.height)
    }

    private func axValue(from reference: CFTypeRef?) -> AXValue? {
        guard let reference else { return nil }
        guard CFGetTypeID(reference) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(reference, to: AXValue.self)
    }

    private func intAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard status == .success, let ref else { return nil }
        if let value = ref as? Int {
            return value
        }
        if let number = ref as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func stringForRange(_ element: AXUIElement, range: CFRange) -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }

        var ref: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &ref
        )
        guard status == .success, let ref else {
            return nil
        }
        if let value = ref as? String {
            return value
        }
        if let attributed = ref as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard status == .success, let ref else { return nil }
        if let value = ref as? String {
            return value
        }
        if let attributed = ref as? NSAttributedString {
            return attributed.string
        }
        return nil
    }
}
