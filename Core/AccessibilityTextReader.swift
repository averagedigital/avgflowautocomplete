import ApplicationServices
import Foundation

final class AccessibilityTextReader {
    struct SelectedTextSnapshot {
        let text: String
        let range: CFRange
    }

    struct ElementTraits {
        let role: String
        let subrole: String
        let isEditable: Bool
        let isSecure: Bool
    }

    // MARK: - Read Context

    /// Read text context from the currently focused UI element.
    /// Returns `nil` if the element is not a text input or text cannot be read.
    func readContext(from focusedElement: AXUIElement, appBundleID: String?) -> TextContext? {
        let element = editableElement(from: focusedElement) ?? focusedElement

        // Never read from secure/password-like fields.
        guard !isSecureTextInput(element) else {
            return nil
        }

        // Step 1: Read full text value
        if let fullText = stringAttribute(element, kAXValueAttribute) {
            // Step 2: Get cursor position via selected text range
            let cursorUTF16Offset: Int
            if let range = selectedRange(element) {
                let utf16Length = (fullText as NSString).length
                cursorUTF16Offset = min(max(0, range.location), utf16Length)
            } else {
                // If we can't read the cursor, assume it's at the end
                cursorUTF16Offset = (fullText as NSString).length
            }

            // Step 3: Build TextContext using the shared TextProcessor
            return TextProcessor.buildContext(
                fullText: fullText,
                cursorUTF16Offset: cursorUTF16Offset,
                appIdentifier: appBundleID
            )
        }

        // Web and rich text fields often don't expose AXValue.
        return readContextViaParameterizedRange(from: element, appBundleID: appBundleID)
    }

    // MARK: - Element Queries

    /// Get the currently focused UI element for a given application.
    func focusedElement(for app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &ref
        )
        guard status == .success, let element = uiElement(from: ref) else {
            return nil
        }
        return element
    }

    /// Check if the focused element is a text input field.
    /// Enhanced to detect code editor elements from IDEs (Xcode, VSCode, JetBrains, Sublime, etc.)
    func isTextInput(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute) ?? ""
        let subrole = stringAttribute(element, kAXSubroleAttribute) ?? ""

        // Standard text input roles
        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            kAXSearchFieldSubrole as String
        ]
        if textRoles.contains(role) {
            return true
        }

        // IDE-specific subroles (Xcode source editor, etc.)
        let codeSubroles: Set<String> = [
            "AXCodeEditor",
            "AXSourceEditor",
            "AXSourceCodeEditor",
            "AXCodeArea",
            "AXPlainText",
        ]
        if codeSubroles.contains(subrole) {
            return true
        }

        // Web areas (e.g. VSCode Electron, Chrome text fields)
        if role == "AXWebArea" {
            if boolAttribute(element, "AXEditable") == true {
                return true
            }
            if selectedRange(element) != nil {
                return true
            }
        }

        // Generic "editable" flag — covers many IDE custom views
        if boolAttribute(element, "AXEditable") == true {
            return true
        }

        // Role description heuristic — widened for code editors
        if let roleDescription = stringAttribute(element, kAXRoleDescriptionAttribute) {
            let lowered = roleDescription.lowercased()
            if lowered.contains("text") || lowered.contains("edit")
                || lowered.contains("code") || lowered.contains("source")
                || lowered.contains("input") || lowered.contains("editor") {
                return true
            }
        }

        // Parameterized text attributes: if element exposes selectable text + value, it's likely an input
        if selectedRange(element) != nil && stringAttribute(element, kAXValueAttribute) != nil {
            return true
        }

        // Fallback: if element exposes AXNumberOfCharacters + selected range, treat as text input
        // (JetBrains IDEs sometimes use custom roles but expose these attributes)
        if selectedRange(element) != nil && intAttribute(element, kAXNumberOfCharactersAttribute as String) != nil {
            return true
        }

        return false
    }

    /// Resolve a practical editable target by walking ancestors.
    /// Needed for some web apps where focused element is a nested non-editable child.
    func editableElement(from element: AXUIElement) -> AXUIElement? {
        if isTextInput(element) {
            return element
        }

        var current: AXUIElement? = element
        for _ in 0..<7 {
            guard let node = current else { break }
            guard let parent = parentElement(of: node) else { break }
            if isTextInput(parent) {
                return parent
            }
            current = parent
        }

        return nil
    }

    /// Compare two contexts for meaningful change.
    func hasMeaningfulChange(previous: TextContext?, current: TextContext) -> Bool {
        guard let previous else {
            return true
        }
        return previous.textBefore != current.textBefore
            || previous.textAfter != current.textAfter
            || previous.language != current.language
    }

    /// Read currently selected text and its range from an editable element.
    /// Returns `nil` when there is no selection or when text cannot be resolved.
    func selectedTextSnapshot(from focusedElement: AXUIElement) -> SelectedTextSnapshot? {
        let element = editableElement(from: focusedElement) ?? focusedElement
        guard !isSecureTextInput(element), let range = selectedRange(element), range.length > 0 else {
            return nil
        }

        let safeRange = CFRange(location: max(0, range.location), length: max(0, range.length))

        if let selected = stringAttribute(element, kAXSelectedTextAttribute),
           !selected.isEmpty {
            return SelectedTextSnapshot(text: selected, range: safeRange)
        }

        if let fullText = stringAttribute(element, kAXValueAttribute) {
            let ns = fullText as NSString
            let safeLocation = min(max(0, safeRange.location), ns.length)
            let safeLength = min(max(0, safeRange.length), max(0, ns.length - safeLocation))
            if safeLength > 0 {
                let text = ns.substring(with: NSRange(location: safeLocation, length: safeLength))
                if !text.isEmpty {
                    return SelectedTextSnapshot(text: text, range: CFRange(location: safeLocation, length: safeLength))
                }
            }
        }

        if let selectedByRange = stringForRange(element, range: safeRange),
           !selectedByRange.isEmpty {
            return SelectedTextSnapshot(text: selectedByRange, range: safeRange)
        }

        return nil
    }

    func elementTraits(for focusedElement: AXUIElement) -> ElementTraits {
        let element = editableElement(from: focusedElement) ?? focusedElement
        let role = stringAttribute(element, kAXRoleAttribute) ?? ""
        let subrole = stringAttribute(element, kAXSubroleAttribute) ?? ""
        let editable = boolAttribute(element, "AXEditable") == true || isTextInput(element)
        return ElementTraits(
            role: role,
            subrole: subrole,
            isEditable: editable,
            isSecure: isSecureTextInput(element)
        )
    }

    // MARK: - Private Helpers

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard status == .success else { return nil }
        guard let ref else { return nil }
        if let value = ref as? String {
            return value
        }
        if let attributed = ref as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard status == .success else { return nil }
        return ref as? Bool
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

    private func isSecureTextInput(_ element: AXUIElement) -> Bool {
        if let subrole = stringAttribute(element, kAXSubroleAttribute),
           subrole == "AXSecureTextField" {
            return true
        }

        if let roleDescription = stringAttribute(element, kAXRoleDescriptionAttribute) {
            let lowered = roleDescription.lowercased()
            if lowered.contains("secure") || lowered.contains("password") {
                return true
            }
        }

        let secureFlags = ["AXSecure", "AXIsSecure", "AXProtectedContent"]
        for flag in secureFlags where boolAttribute(element, flag) == true {
            return true
        }

        return false
    }

    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &ref
        )
        guard status == .success, let axValue = axValue(from: ref) else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func readContextViaParameterizedRange(from element: AXUIElement, appBundleID: String?) -> TextContext? {
        guard let selection = selectedRange(element) else {
            return nil
        }

        let safeLocation = max(0, selection.location)
        let safeLength = max(0, selection.length)
        let charsTotal = max(
            safeLocation + safeLength,
            intAttribute(element, kAXNumberOfCharactersAttribute as String) ?? 0
        )

        let beforeStart = max(0, safeLocation - 4096)
        let beforeLength = max(0, safeLocation - beforeStart)
        let afterStart = min(charsTotal, safeLocation + safeLength)
        let afterLength = max(0, min(1536, charsTotal - afterStart))

        let before = stringForRange(element, range: CFRange(location: beforeStart, length: beforeLength)) ?? ""
        let after = stringForRange(element, range: CFRange(location: afterStart, length: afterLength)) ?? ""

        if before.isEmpty && after.isEmpty {
            return nil
        }

        return TextProcessor.buildContext(
            fullText: before + after,
            cursorOffset: before.count,
            appIdentifier: appBundleID
        )
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

    private func parentElement(of element: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &ref
        )
        guard status == .success else { return nil }
        return uiElement(from: ref)
    }

    private func axValue(from reference: CFTypeRef?) -> AXValue? {
        guard let reference else { return nil }
        guard CFGetTypeID(reference) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(reference, to: AXValue.self)
    }

    private func uiElement(from reference: CFTypeRef?) -> AXUIElement? {
        guard let reference else { return nil }
        guard CFGetTypeID(reference) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(reference, to: AXUIElement.self)
    }
}
