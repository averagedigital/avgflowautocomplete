import AppKit

@MainActor
final class SuggestionPanelController {
    private static let defaultGeometryFallbackPolicy = GeometryFallbackPolicy(
        allowsSyntheticCaret: true,
        allowsInputFallback: true,
        allowsMouseFallback: true
    )

    private enum BubblePlacement {
        case inline
        case below
        case above
    }

    private struct Layout {
        let isWrapped: Bool
        let textWidth: CGFloat
        let panelSize: CGSize
        let placement: BubblePlacement
        let presentationStyle: SuggestionPresentationStyle
    }

    private struct ResolvedAnchor {
        let bounds: NSRect
        let quality: CursorPositionResolver.CursorAnchor.Quality
    }

    private let panel: SuggestionPanel
    private let cursorResolver: CursorPositionResolver
    private var contentView: SuggestionPanelContentView?
    private var currentLoading = false

    private(set) var isVisible: Bool = false
    private(set) var currentSuggestion: String = ""
    private(set) var currentSuggestions: [String] = []
    private(set) var selectedSuggestionIndex: Int = 0

    var onSuggestionClicked: ((Int) -> Void)?
    var onSelectionCycleRequested: ((Int) -> Void)?

    private let panelFont = NSFont(name: "Inter", size: 17) ?? NSFont.systemFont(ofSize: 17)
    private let badgeAndSpacingReserve: CGFloat = 60

    /// Streaming state
    private var streamTask: Task<Void, Never>?

    init() {
        panel = SuggestionPanel()
        cursorResolver = CursorPositionResolver()

        // Watch for system appearance changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTheme()
            }
        }
    }

    // MARK: - Theme

    /// Returns the overlay theme, following system appearance.
    private var resolvedTheme: OverlayThemePreset {
        let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard
        let saved = defaults.string(forKey: "overlayThemePreset") ?? "system"
        switch saved {
        case "darkChrome":  return .darkChrome
        case "light":       return .light
        case "liquidGlass": return .liquidGlass
        default:            return OverlayThemePreset.system
        }
    }

    private func refreshTheme() {
        contentView?.themePreset = resolvedTheme
    }

    // MARK: - Show / Hide

    func show(
        suggestion: String,
        near element: AXUIElement,
        isLoading: Bool = false,
        source: CompletionSource = .hybrid,
        confidence: Double = 0.0,
        modelName: String? = nil,
        geometryFallbackPolicy: GeometryFallbackPolicy = defaultGeometryFallbackPolicy
    ) {
        show(
            suggestions: [suggestion],
            selectedIndex: 0,
            near: element,
            isLoading: isLoading,
            source: source,
            confidence: confidence,
            modelName: modelName,
            geometryFallbackPolicy: geometryFallbackPolicy
        )
    }

    func show(
        suggestions: [String],
        selectedIndex: Int,
        near element: AXUIElement,
        isLoading: Bool = false,
        source: CompletionSource = .hybrid,
        confidence: Double = 0.0,
        modelName: String? = nil,
        geometryFallbackPolicy: GeometryFallbackPolicy = defaultGeometryFallbackPolicy
    ) {
        _ = source
        _ = confidence
        _ = modelName

        let cleanedSuggestions = suggestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !(cleanedSuggestions.isEmpty && !isLoading) else {
            hide()
            return
        }
        let inputBounds = cursorResolver.inputBounds(for: element)
        guard let anchor = resolvedAnchor(
            for: element,
            inputBounds: inputBounds,
            geometryFallbackPolicy: geometryFallbackPolicy
        ) else {
            hide()
            return
        }
        currentSuggestions = cleanedSuggestions
        currentSuggestion = cleanedSuggestions.first ?? ""
        selectedSuggestionIndex = cleanedSuggestions.isEmpty ? 0 : min(max(0, selectedIndex), cleanedSuggestions.count - 1)
        currentLoading = isLoading
        let wasVisible = isVisible
        isVisible = true
        let caretBounds = anchor.bounds
        let screen = screenContaining(point: NSPoint(x: caretBounds.midX, y: caretBounds.midY))
        let screenFrame = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        let horizontalBounds = horizontalPlacementBounds(inputBounds: inputBounds, screenFrame: screenFrame)
        let verticalBounds = verticalPlacementBounds(inputBounds: inputBounds, screenFrame: screenFrame)
        let layout = makeLayout(
            suggestions: cleanedSuggestions,
            horizontalBounds: horizontalBounds,
            verticalBounds: verticalBounds,
            caretBounds: caretBounds,
            anchorQuality: anchor.quality,
            isLoading: isLoading
        )

        let view: SuggestionPanelContentView
        if let existing = contentView {
            view = existing
        } else {
            view = SuggestionPanelContentView()
            view.themePreset = resolvedTheme
            view.onSuggestionClicked = { [weak self] index in
                self?.onSuggestionClicked?(index)
            }
            view.onSelectionCycleRequested = { [weak self] delta in
                self?.onSelectionCycleRequested?(delta)
            }
            panel.contentView = view
            contentView = view
        }

        view.suggestion = cleanedSuggestions.first ?? ""
        view.suggestions = cleanedSuggestions
        view.selectedIndex = selectedSuggestionIndex
        view.isLoading = isLoading
        view.isWrapped = layout.isWrapped
        view.presentationStyle = layout.presentationStyle
        view.maxTextWidth = layout.textWidth
        view.themePreset = resolvedTheme

        view.frame = CGRect(origin: .zero, size: layout.panelSize)
        panel.setContentSize(layout.panelSize)
        panel.hasShadow = layout.presentationStyle == .bubble

        let positioned = positionedOrigin(
            for: layout,
            panelSize: layout.panelSize,
            caretBounds: caretBounds,
            inputBounds: inputBounds,
            horizontalBounds: horizontalBounds,
            verticalBounds: verticalBounds,
            screenFrame: screenFrame
        )
        view.verticalOrientation = layout.presentationStyle == .inlineGhost
            ? .inline
            : bubbleOrientation(for: positioned.resolvedPlacement)
        panel.setFrameOrigin(positioned.origin)

        if wasVisible {
            panel.alphaValue = 1
            panel.orderFront(nil)
        } else {
            panel.fadeIn(slideOffset: layout.presentationStyle == .inlineGhost ? 0 : 4)
        }
    }

    static func allowsAnchorQuality(
        _ quality: CursorPositionResolver.CursorAnchor.Quality,
        geometryFallbackPolicy: GeometryFallbackPolicy
    ) -> Bool {
        switch quality {
        case .preciseCaret:
            return true
        case .syntheticCaret:
            return geometryFallbackPolicy.allowsSyntheticCaret
        case .inputFallback:
            return geometryFallbackPolicy.allowsInputFallback
        }
    }

    private func resolvedAnchor(
        for element: AXUIElement,
        inputBounds: NSRect?,
        geometryFallbackPolicy: GeometryFallbackPolicy
    ) -> ResolvedAnchor? {
        if let caretAnchor = cursorResolver.caretAnchor(for: element) {
            guard Self.allowsAnchorQuality(
                caretAnchor.quality,
                geometryFallbackPolicy: geometryFallbackPolicy
            ) else {
                return nil
            }
            return ResolvedAnchor(bounds: caretAnchor.bounds, quality: caretAnchor.quality)
        }

        if let inputBounds, geometryFallbackPolicy.allowsInputFallback {
            return ResolvedAnchor(
                bounds: NSRect(
                    x: min(inputBounds.maxX - 24, inputBounds.minX + 24),
                    y: max(inputBounds.minY + 6, inputBounds.maxY - 28),
                    width: 2,
                    height: 22
                ),
                quality: .inputFallback
            )
        }

        guard geometryFallbackPolicy.allowsMouseFallback else {
            return nil
        }
        let mouseLocation = NSEvent.mouseLocation
        return ResolvedAnchor(
            bounds: NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 2, height: 22),
            quality: .inputFallback
        )
    }

    func showLoading(
        near element: AXUIElement,
        geometryFallbackPolicy: GeometryFallbackPolicy = defaultGeometryFallbackPolicy
    ) {
        show(
            suggestion: "",
            near: element,
            isLoading: true,
            geometryFallbackPolicy: geometryFallbackPolicy
        )
    }

    func hide() {
        streamTask?.cancel()
        streamTask = nil
        contentView?.isLoading = false
        guard isVisible else { return }
        isVisible = false
        currentSuggestion = ""
        currentSuggestions = []
        selectedSuggestionIndex = 0
        panel.fadeOut()
    }

    func updatePosition(near element: AXUIElement) {
        guard isVisible else { return }
        show(
            suggestions: currentSuggestions.isEmpty ? [currentSuggestion] : currentSuggestions,
            selectedIndex: selectedSuggestionIndex,
            near: element,
            isLoading: currentLoading
        )
    }

    func updateSelection(index: Int) {
        guard !currentSuggestions.isEmpty else { return }
        selectedSuggestionIndex = min(max(0, index), currentSuggestions.count - 1)
        contentView?.selectedIndex = selectedSuggestionIndex
        contentView?.needsDisplay = true
    }

    // MARK: - Layout

    static func presentationStyleForLayout(
        suggestionCount: Int,
        isWrapped: Bool,
        anchorQuality: CursorPositionResolver.CursorAnchor.Quality
    ) -> SuggestionPresentationStyle {
        guard !isWrapped, suggestionCount == 1, anchorQuality.supportsInlineGhost else {
            return .bubble
        }
        return .inlineGhost
    }

    private func makeLayout(
        suggestions: [String],
        horizontalBounds: ClosedRange<CGFloat>,
        verticalBounds: ClosedRange<CGFloat>,
        caretBounds: NSRect,
        anchorQuality: CursorPositionResolver.CursorAnchor.Quality,
        isLoading: Bool
    ) -> Layout {
        let measuredText = measuredSuggestionForLayout(suggestions)
        let fullTextWidth = ceil((measuredText as NSString).size(withAttributes: [.font: panelFont]).width)
        let isPalette = suggestions.count > 1

        let inlineRightSpace = max(0, horizontalBounds.upperBound - (caretBounds.maxX + 3))
        let inlineTextWidthLimit = max(96, min(560, inlineRightSpace - badgeAndSpacingReserve))
        let forceWrap = inlineTextWidthLimit < 200 || isPalette
        let shouldWrap = forceWrap || fullTextWidth > inlineTextWidthLimit

        let view = contentView ?? SuggestionPanelContentView()

        if shouldWrap {
            let availableWindowWidth = max(280, (horizontalBounds.upperBound - horizontalBounds.lowerBound) - 14)
            let wrappedTextWidth = max(220, availableWindowWidth - badgeAndSpacingReserve)
            var placement = preferredWrappedPlacement(caretBounds: caretBounds, verticalBounds: verticalBounds)
            var wrappedHeightLimit = max(72, wrappedAvailableHeight(for: placement, caretBounds: caretBounds, verticalBounds: verticalBounds) - 10)
            let alternate: BubblePlacement = (placement == .below) ? .above : .below
            let alternateHeight = max(72, wrappedAvailableHeight(for: alternate, caretBounds: caretBounds, verticalBounds: verticalBounds) - 10)
            if alternateHeight > wrappedHeightLimit + 28 {
                placement = alternate
                wrappedHeightLimit = alternateHeight
            }

            view.suggestion = suggestions.first ?? ""
            view.suggestions = suggestions
            view.selectedIndex = selectedSuggestionIndex
            view.isLoading = isLoading
            view.isWrapped = true
            view.maxTextWidth = wrappedTextWidth
            view.maxWrappedTextHeight = min(900, wrappedHeightLimit)
            var panelSize = view.intrinsicContentSize
            if panelSize.height > wrappedHeightLimit {
                view.maxWrappedTextHeight = max(44, wrappedHeightLimit - 8)
                panelSize = view.intrinsicContentSize
            }
            return Layout(
                isWrapped: true,
                textWidth: wrappedTextWidth,
                panelSize: panelSize,
                placement: placement,
                presentationStyle: .bubble
            )
        }

        view.suggestion = suggestions.first ?? ""
        view.suggestions = suggestions
        view.selectedIndex = selectedSuggestionIndex
        view.isLoading = isLoading
        view.isWrapped = false
        view.maxTextWidth = inlineTextWidthLimit
        view.maxWrappedTextHeight = 320
        let panelSize = view.intrinsicContentSize
        let presentationStyle = Self.presentationStyleForLayout(
            suggestionCount: suggestions.count,
            isWrapped: false,
            anchorQuality: anchorQuality
        )
        return Layout(
            isWrapped: false,
            textWidth: inlineTextWidthLimit,
            panelSize: panelSize,
            placement: .inline,
            presentationStyle: presentationStyle
        )
    }

    private func positionedOrigin(
        for layout: Layout,
        panelSize: CGSize,
        caretBounds: NSRect,
        inputBounds: NSRect?,
        horizontalBounds: ClosedRange<CGFloat>,
        verticalBounds: ClosedRange<CGFloat>,
        screenFrame: NSRect
    ) -> (origin: NSPoint, resolvedPlacement: BubblePlacement) {
        let minX = horizontalBounds.lowerBound
        let maxX = horizontalBounds.upperBound
        _ = screenFrame
        let minY = verticalBounds.lowerBound
        let maxY = verticalBounds.upperBound

        var x: CGFloat
        var y: CGFloat
        var resolvedPlacement: BubblePlacement = .inline

        if layout.isWrapped {
            let baseX = (inputBounds?.minX ?? caretBounds.minX) + 6
            x = min(max(baseX, minX), maxX - panelSize.width)

            let wrappedPosition = resolveWrappedPosition(
                panelSize: panelSize,
                x: x,
                caretBounds: caretBounds,
                inputBounds: inputBounds,
                horizontalBounds: horizontalBounds,
                verticalBounds: verticalBounds,
                preferredPlacement: layout.placement
            )
            x = wrappedPosition.x
            y = wrappedPosition.y
            resolvedPlacement = wrappedPosition.placement
        } else {
            x = caretBounds.maxX + 3
            y = caretBounds.minY + (caretBounds.height - panelSize.height) * 0.5
            x = min(max(x, minX), maxX - panelSize.width)
            y = min(max(y, minY), maxY - panelSize.height)
        }

        return (NSPoint(x: x, y: y), resolvedPlacement)
    }

    private func horizontalPlacementBounds(inputBounds: NSRect?, screenFrame: NSRect) -> ClosedRange<CGFloat> {
        var minX = screenFrame.minX + 4
        var maxX = screenFrame.maxX - 4

        if let inputBounds {
            minX = max(minX, inputBounds.minX + 2)
            maxX = min(maxX, inputBounds.maxX - 2)
        }

        if maxX - minX < 180 {
            minX = screenFrame.minX + 4
            maxX = screenFrame.maxX - 4
        }

        return minX...maxX
    }

    private func verticalPlacementBounds(inputBounds: NSRect?, screenFrame: NSRect) -> ClosedRange<CGFloat> {
        var minY = screenFrame.minY + 2
        var maxY = screenFrame.maxY - 2

        if let inputBounds {
            minY = max(minY, inputBounds.minY + 2)
            maxY = min(maxY, inputBounds.maxY - 2)
        }

        if maxY - minY < 80 {
            minY = screenFrame.minY + 2
            maxY = screenFrame.maxY - 2
        }
        return minY...maxY
    }

    private func resolveWrappedPosition(
        panelSize: CGSize,
        x: CGFloat,
        caretBounds: NSRect,
        inputBounds: NSRect?,
        horizontalBounds: ClosedRange<CGFloat>,
        verticalBounds: ClosedRange<CGFloat>,
        preferredPlacement: BubblePlacement
    ) -> (x: CGFloat, y: CGFloat, placement: BubblePlacement) {
        let minY = verticalBounds.lowerBound
        let maxY = verticalBounds.upperBound
        let maxAvailableY = max(minY, maxY - panelSize.height)
        let gap: CGFloat = 14
        let edgeInset: CGFloat = 8

        let minX = horizontalBounds.lowerBound
        let maxX = max(minX, horizontalBounds.upperBound - panelSize.width)
        let inputMinX = inputBounds?.minX ?? minX
        let inputMaxX = inputBounds?.maxX ?? horizontalBounds.upperBound
        let leftAlignedX = min(max((inputMinX + 6), minX), maxX)
        let centeredX = min(max(caretBounds.midX - panelSize.width * 0.5, minX), maxX)
        let rightAlignedX = min(max((inputMaxX - panelSize.width - 6), minX), maxX)
        var xCandidates: [CGFloat] = []
        for candidate in [x, leftAlignedX, centeredX, rightAlignedX] {
            if !xCandidates.contains(where: { abs($0 - candidate) < 0.5 }) {
                xCandidates.append(candidate)
            }
        }

        let caretPad = max(12, min(34, max(16, caretBounds.height * 1.45)))
        let protectedCaretZone = NSRect(
            x: caretBounds.minX - 34,
            y: caretBounds.minY - caretPad,
            width: caretBounds.width + 68,
            height: caretBounds.height + caretPad * 2
        )

        let typingLinePadY = max(10, min(24, caretBounds.height * 1.05))
        let typingZone = NSRect(
            x: inputMinX + 2,
            y: caretBounds.minY - typingLinePadY,
            width: max(80, (inputMaxX - inputMinX) - 4),
            height: caretBounds.height + typingLinePadY * 2
        )

        let belowEdge = minY + edgeInset
        let aboveEdge = maxAvailableY - edgeInset
        let belowCaret = caretBounds.minY - panelSize.height - gap
        let aboveCaret = caretBounds.maxY + gap
        let centeredNearCaret = caretBounds.midY - panelSize.height * 0.5

        let candidates: [(BubblePlacement, CGFloat)] = {
            if preferredPlacement == .above {
                return [(.above, aboveCaret), (.below, belowCaret), (.above, centeredNearCaret), (.above, aboveEdge), (.below, belowEdge)]
            }
            return [(.below, belowCaret), (.above, aboveCaret), (.below, centeredNearCaret), (.below, belowEdge), (.above, aboveEdge)]
        }()

        func clampedY(_ y: CGFloat) -> CGFloat {
            min(max(y, minY), maxAvailableY)
        }

        func overlapArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
            let intersection = lhs.intersection(rhs)
            guard !intersection.isNull else { return 0 }
            return intersection.width * intersection.height
        }

        var bestFallback: (x: CGFloat, y: CGFloat, placement: BubblePlacement, score: CGFloat)?

        for (placement, candidateY) in candidates {
            let fittedY = clampedY(candidateY)
            for candidateX in xCandidates {
                let rect = NSRect(x: candidateX, y: fittedY, width: panelSize.width, height: panelSize.height)
                let overlapsTyping = rect.intersects(typingZone)
                let overlapsCaret = rect.intersects(protectedCaretZone)
                if !overlapsTyping && !overlapsCaret {
                    return (candidateX, fittedY, placement)
                }

                let typingOverlap = overlapArea(rect, typingZone)
                let caretOverlap = overlapArea(rect, protectedCaretZone)
                let clampPenalty = abs(candidateY - fittedY) * 0.8
                let caretDistancePenalty = abs(rect.midY - caretBounds.midY) * 0.25
                let score = typingOverlap * 2.0 + caretOverlap * 2.8 + clampPenalty + caretDistancePenalty
                if bestFallback == nil || score < bestFallback!.score {
                    bestFallback = (candidateX, fittedY, placement, score)
                }
            }
        }

        if let bestFallback {
            return (bestFallback.x, bestFallback.y, bestFallback.placement)
        }

        let fallbackPlacement: BubblePlacement = (preferredPlacement == .above) ? .above : .below
        let fallbackY = clampedY(fallbackPlacement == .above ? aboveCaret : belowCaret)
        return (leftAlignedX, fallbackY, fallbackPlacement)
    }

    private func measuredSuggestionForLayout(_ suggestions: [String]) -> String {
        suggestions.joined(separator: "\n")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func preferredWrappedPlacement(
        caretBounds: NSRect,
        verticalBounds: ClosedRange<CGFloat>
    ) -> BubblePlacement {
        let gap: CGFloat = 12
        let belowSpace = max(0, caretBounds.minY - verticalBounds.lowerBound - gap)
        let aboveSpace = max(0, verticalBounds.upperBound - caretBounds.maxY - gap)
        let totalHeight = max(1, verticalBounds.upperBound - verticalBounds.lowerBound)
        let caretRelativeY = (caretBounds.midY - verticalBounds.lowerBound) / totalHeight

        if caretRelativeY >= 0.60 {
            if belowSpace > 34 { return .below }
            return .above
        }
        if caretRelativeY <= 0.40 {
            if aboveSpace > 34 { return .above }
            return .below
        }

        return belowSpace >= aboveSpace ? .below : .above
    }

    private func wrappedAvailableHeight(
        for placement: BubblePlacement,
        caretBounds: NSRect,
        verticalBounds: ClosedRange<CGFloat>
    ) -> CGFloat {
        let gap: CGFloat = 12
        switch placement {
        case .below:
            return max(0, caretBounds.minY - verticalBounds.lowerBound - gap)
        case .above:
            return max(0, verticalBounds.upperBound - caretBounds.maxY - gap)
        case .inline:
            return max(0, verticalBounds.upperBound - verticalBounds.lowerBound)
        }
    }

    private func bubbleOrientation(for placement: BubblePlacement) -> SuggestionBubbleVerticalOrientation {
        switch placement {
        case .below: return .below
        case .above: return .above
        case .inline: return .inline
        }
    }
}
