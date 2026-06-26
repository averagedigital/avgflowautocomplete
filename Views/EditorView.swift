import SwiftUI
import AppKit

struct EditorView: View {
    @StateObject private var viewModel = EditorViewModel()
    @State private var caretRect: CGRect = .zero
    @State private var isComposingText = false
    @State private var hasSelection = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let editorHorizontalInset = AITheme.spacingS + 4
    private let editorTopInset = AITheme.spacingS + 4
    private let editorFontSize: CGFloat = 17

    @AppStorage(
        Constants.UserDefaultsKeys.suggestionTriggerMode,
        store: AppGroupManager.shared.sharedUserDefaults() ?? .standard
    )
    private var suggestionTriggerModeRaw = "manualHotkey"

    @AppStorage(
        Constants.UserDefaultsKeys.manualTriggerKeyCode,
        store: AppGroupManager.shared.sharedUserDefaults() ?? .standard
    )
    private var manualTriggerKeyCode = 49

    @AppStorage(
        Constants.UserDefaultsKeys.manualTriggerModifiers,
        store: AppGroupManager.shared.sharedUserDefaults() ?? .standard
    )
    private var manualTriggerModifiersRaw = Int(CGEventFlags.maskAlternate.rawValue)

    private let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard

    private var hasAPIKey: Bool {
        let key = APIKeyStore.read() ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentMode: String {
        defaults.string(forKey: Constants.UserDefaultsKeys.completionMode) ?? "hybrid"
    }

    private var needsSetup: Bool {
        // Cloud/hybrid mode without API key = can't complete
        if currentMode != "localOnly" && !hasAPIKey { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Setup guidance banner (if needed)
            if needsSetup {
                setupBanner
            }

            ZStack(alignment: .topLeading) {
                if viewModel.text.isEmpty && viewModel.ghostSuggestion.isEmpty && !needsSetup {
                    VStack(spacing: AITheme.spacingM) {
                        Spacer()
                        AITheme.emptyState(
                            icon: "keyboard",
                            title: L.isRussian ? "Тестовый редактор" : "Test Editor",
                            subtitle: L.isRussian
                                ? "Начните печатать — подсказка появится в подходящий момент или после . ! ?.\nTab принимает, Esc отклоняет."
                                : "Start typing — suggestion appears at the right moment or after . ! ?.\nTab accepts, Esc dismisses."
                        )
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }

                InlineEditorTextView(
                    text: viewModel.text,
                    editorFontSize: editorFontSize,
                    manualTriggerEnabled: suggestionTriggerModeRaw == "manualHotkey",
                    manualTriggerKeyCode: manualTriggerKeyCode,
                    manualTriggerModifiers: normalizedEditorManualModifiers(
                        rawValue: UInt64(max(0, manualTriggerModifiersRaw))
                    ),
                    onTextChange: { newText, isComposing in
                        Task { @MainActor in
                            isComposingText = isComposing
                            viewModel.userDidChangeText(newText, isComposing: isComposing)
                        }
                    },
                    onTab: {
                        viewModel.handleTabPressed()
                    },
                    onManualTrigger: {
                        viewModel.handleManualTriggerPressed()
                    },
                    onCompositionChange: { composing in
                        Task { @MainActor in
                            isComposingText = composing
                            viewModel.setCompositionState(composing)
                        }
                    },
                    onSelectionChange: { selected in
                        Task { @MainActor in
                            hasSelection = selected
                        }
                    },
                    onCaretRectChange: { newRect in
                        Task { @MainActor in
                            caretRect = newRect
                        }
                    }
                )
                .padding(.horizontal, editorHorizontalInset)
                .padding(.top, editorTopInset)
                .padding(.bottom, AITheme.spacingS + 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if !viewModel.ghostSuggestion.isEmpty && !isComposingText && !hasSelection {
                    GeometryReader { proxy in
                        let containerWidth = proxy.size.width
                        let rightSpace = containerWidth - (editorHorizontalInset + caretRect.maxX + 8)
                        let estimatedSuggestionWidth = estimateSuggestionWidth(
                            viewModel.ghostSuggestion,
                            bodyFont: NSFont(name: "Inter", size: editorFontSize) ?? NSFont.systemFont(ofSize: editorFontSize)
                        )
                        let shouldWrapToNextLine = rightSpace < 180 || estimatedSuggestionWidth > rightSpace
                        let wrappedWidth = max(220, containerWidth - (editorHorizontalInset * 2) - 10)
                        let inlineWidth = min(max(160, rightSpace), wrappedWidth)
                        let suggestionWidth = shouldWrapToNextLine ? wrappedWidth : inlineWidth
                        let xOffset = shouldWrapToNextLine
                            ? editorHorizontalInset + 2
                            : editorHorizontalInset + caretRect.maxX + 4
                        let yOffset = shouldWrapToNextLine
                            ? editorTopInset + caretRect.maxY + 4
                            : editorTopInset + caretRect.minY

                        HStack(spacing: 6) {
                            Text(viewModel.ghostSuggestion)
                                .font(.custom("Inter", size: editorFontSize))
                                .foregroundStyle(AITheme.accentMint.opacity(0.96))
                                .lineLimit(shouldWrapToNextLine ? 4 : 1)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Tab")
                                .font(AITheme.fontCaption2.weight(.semibold))
                                .foregroundStyle(AITheme.textPrimary.opacity(0.92))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(AITheme.accentMint.opacity(0.2)))
                        }
                        .frame(width: suggestionWidth, alignment: .leading)
                        .allowsHitTesting(false)
                        .offset(x: xOffset, y: yOffset)
                    }
                }

                // Error / Loading indicator
                VStack {
                    if let error = viewModel.completionError {
                        errorBanner(error)
                    } else if viewModel.isLoading {
                        TypingIndicator()
                    }
                }
                .padding(.top, AITheme.spacingM + 2)
                .padding(.trailing, AITheme.spacingM + 4)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.black.opacity(0.7))
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
            value: viewModel.completionError
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
            value: viewModel.isLoading
        )
    }

    // MARK: - Setup Banner

    private var setupBanner: some View {
        HStack(spacing: AITheme.spacingS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(L.isRussian
                     ? "Автодополнение не настроено"
                     : "Autocomplete not configured")
                    .font(AITheme.fontCaptionBold)

                if !hasAPIKey && currentMode != "localOnly" {
                    Text(L.isRussian
                         ? "Добавьте API ключ в Модели и Провайдеры, или переключитесь на Local Only."
                         : "Add an API key in Models & Providers, or switch to Local Only mode.")
                        .font(AITheme.fontCaption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(AITheme.spacingS + 4)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(error)
        }
        .font(AITheme.fontCaptionBold)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.9), in: Capsule())
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel(L.isRussian ? "Ошибка: \(error)" : "Error: \(error)")
    }
}

// MARK: - NSViewRepresentable for NSTextView

private func estimateSuggestionWidth(_ text: String, bodyFont: NSFont) -> CGFloat {
    let textWidth = (text as NSString).size(withAttributes: [.font: bodyFont]).width
    // Add room for spacing + Tab capsule.
    return textWidth + 56
}

private func normalizedEditorManualModifiers(rawValue: UInt64) -> NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if rawValue & CGEventFlags.maskShift.rawValue != 0 { flags.insert(.shift) }
    if rawValue & CGEventFlags.maskControl.rawValue != 0 { flags.insert(.control) }
    if rawValue & CGEventFlags.maskAlternate.rawValue != 0 { flags.insert(.option) }
    if rawValue & CGEventFlags.maskCommand.rawValue != 0 { flags.insert(.command) }
    return flags
}

private struct InlineEditorTextView: NSViewRepresentable {
    let text: String
    let editorFontSize: CGFloat
    let manualTriggerEnabled: Bool
    let manualTriggerKeyCode: Int
    let manualTriggerModifiers: NSEvent.ModifierFlags
    let onTextChange: (String, Bool) -> Void
    let onTab: () -> Void
    let onManualTrigger: () -> Void
    let onCompositionChange: (Bool) -> Void
    let onSelectionChange: (Bool) -> Void
    let onCaretRectChange: (CGRect) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = TabAwareTextView.makeScrollableTextView()
        guard let textView = scrollView.documentView as? TabAwareTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        let editorFont = NSFont(name: "Inter", size: editorFontSize) ?? NSFont.systemFont(ofSize: editorFontSize)
        textView.font = editorFont
        textView.typingAttributes[.font] = editorFont
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.onTabPressed = onTab
        textView.manualTriggerEnabled = manualTriggerEnabled
        textView.manualTriggerKeyCode = manualTriggerKeyCode
        textView.manualTriggerModifiers = manualTriggerModifiers
        textView.onManualTriggerPressed = onManualTrigger
        textView.onCompositionStateChanged = onCompositionChange
        textView.onSelectionStateChanged = onSelectionChange
        textView.onCaretRectChanged = onCaretRectChange
        textView.string = text
        textView.publishCaretRect()
        textView.publishCompositionState()
        textView.publishSelectionState()

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = AITheme.buttonRadius
        scrollView.layer?.masksToBounds = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TabAwareTextView else { return }
        textView.onTabPressed = onTab
        textView.manualTriggerEnabled = manualTriggerEnabled
        textView.manualTriggerKeyCode = manualTriggerKeyCode
        textView.manualTriggerModifiers = manualTriggerModifiers
        textView.onManualTriggerPressed = onManualTrigger
        textView.onCompositionStateChanged = onCompositionChange
        textView.onSelectionStateChanged = onSelectionChange
        textView.onCaretRectChanged = onCaretRectChange

        guard textView.string != text else {
            textView.publishCaretRect()
            textView.publishCompositionState()
            textView.publishSelectionState()
            return
        }

        context.coordinator.isProgrammaticUpdate = true
        textView.string = text
        context.coordinator.isProgrammaticUpdate = false
        textView.publishCaretRect()
        textView.publishCompositionState()
        textView.publishSelectionState()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, onCompositionChange: onCompositionChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var isProgrammaticUpdate = false
        let onTextChange: (String, Bool) -> Void
        let onCompositionChange: (Bool) -> Void

        init(
            onTextChange: @escaping (String, Bool) -> Void,
            onCompositionChange: @escaping (Bool) -> Void
        ) {
            self.onTextChange = onTextChange
            self.onCompositionChange = onCompositionChange
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate else {
                return
            }
            guard let textView = notification.object as? TabAwareTextView else {
                return
            }
            let newString = textView.string
            let isComposing = textView.hasMarkedText()
            DispatchQueue.main.async {
                self.onTextChange(newString, isComposing)
                self.onCompositionChange(isComposing)
            }
            textView.publishCaretRect()
            textView.publishCompositionState()
            textView.publishSelectionState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? TabAwareTextView else {
                return
            }
            let isComposing = textView.hasMarkedText()
            DispatchQueue.main.async {
                self.onCompositionChange(isComposing)
            }
            textView.publishCaretRect()
            textView.publishCompositionState()
            textView.publishSelectionState()
        }
    }
}

// MARK: - TabAwareTextView (NSTextView subclass)

private final class TabAwareTextView: NSTextView {
    var onTabPressed: (() -> Void)?
    var onManualTriggerPressed: (() -> Void)?
    var manualTriggerEnabled: Bool = false
    var manualTriggerKeyCode: Int = 49
    var manualTriggerModifiers: NSEvent.ModifierFlags = [.option]
    var onCompositionStateChanged: ((Bool) -> Void)?
    var onSelectionStateChanged: ((Bool) -> Void)?
    var onCaretRectChanged: ((CGRect) -> Void)?

    override func keyDown(with event: NSEvent) {
        let normalizedModifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if manualTriggerEnabled,
           Int(event.keyCode) == manualTriggerKeyCode,
           normalizedModifiers == manualTriggerModifiers {
            onManualTriggerPressed?()
            return
        }

        if event.keyCode == 48 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onTabPressed?()
            return
        }
        super.keyDown(with: event)
        publishCompositionState()
        publishSelectionState()
        publishCaretRect()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        publishCompositionState()
        publishSelectionState()
        publishCaretRect()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        publishCompositionState()
        publishSelectionState()
        publishCaretRect()
    }

    func publishCompositionState() {
        guard let onCompositionStateChanged else { return }
        let composing = hasMarkedText()
        DispatchQueue.main.async {
            onCompositionStateChanged(composing)
        }
    }

    func publishSelectionState() {
        guard let onSelectionStateChanged else { return }
        let selected = selectedRange().length > 0
        DispatchQueue.main.async {
            onSelectionStateChanged(selected)
        }
    }

    func publishCaretRect() {
        guard let onCaretRectChanged else { return }
        guard let window else {
            DispatchQueue.main.async {
                onCaretRectChanged(.zero)
            }
            return
        }

        let caretLocation = max(0, selectedRange().location)
        let screenRect = firstRect(forCharacterRange: NSRange(location: caretLocation, length: 0), actualRange: nil)
        let windowRect = window.convertFromScreen(screenRect)
        var localRect = convert(windowRect, from: nil)

        if !isFlipped {
            localRect.origin.y = bounds.height - localRect.maxY
        }

        let isFiniteRect = localRect.origin.x.isFinite
            && localRect.origin.y.isFinite
            && localRect.size.width.isFinite
            && localRect.size.height.isFinite
        if !isFiniteRect {
            DispatchQueue.main.async {
                onCaretRectChanged(.zero)
            }
            return
        }

        DispatchQueue.main.async {
            onCaretRectChanged(localRect)
        }
    }

    static func makeScrollableTextView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = TabAwareTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let textContainer = textView.textContainer
        textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }
}
