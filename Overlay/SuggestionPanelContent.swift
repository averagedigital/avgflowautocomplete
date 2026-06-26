import AppKit

// MARK: - Theme Preset

enum OverlayThemePreset: String, CaseIterable {
    case darkChrome
    case light
    case liquidGlass

    /// Automatically selects based on system appearance.
    static var system: OverlayThemePreset {
        let name = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return (name == .darkAqua) ? .darkChrome : .light
    }
}

enum SuggestionBubbleVerticalOrientation {
    case below
    case above
    case inline
}

enum SuggestionPresentationStyle {
    case bubble
    case inlineGhost
}

// MARK: - Theme Colors (resolved once per draw)

private struct ResolvedPalette {
    let bubbleFill: NSColor
    let bubbleFillAlt: NSColor
    let textColor: NSColor
    let badgeTextColor: NSColor
    let badgeBgColor: NSColor
    let badgeBorderColor: NSColor
    let bubbleBorderGradient: [NSColor]
    let innerStroke: NSColor
    let shadowColor: NSColor
    let loadingDotsColor: NSColor
    let orientationAccentColor: NSColor
    let glowColor: NSColor
    let pointerColor: NSColor
    let useVFX: Bool         // whether to show NSVisualEffectView
    let vfxMaterial: NSVisualEffectView.Material

    // ── Dark Chrome ──────────────────────────────
    static let darkChrome = ResolvedPalette(
        bubbleFill: NSColor(red: 0.06, green: 0.08, blue: 0.07, alpha: 0.84),
        bubbleFillAlt: NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 0.70),
        textColor: NSColor(red: 0.18, green: 1.00, blue: 0.78, alpha: 0.97),
        badgeTextColor: NSColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 0.95),
        badgeBgColor: NSColor(red: 0.00, green: 1.00, blue: 0.62, alpha: 0.14),
        badgeBorderColor: NSColor(red: 0.00, green: 1.00, blue: 0.62, alpha: 0.42),
        bubbleBorderGradient: [
            NSColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 0.30),
            NSColor.white.withAlphaComponent(0.12),
            NSColor(red: 0.00, green: 1.0, blue: 0.62, alpha: 0.28),
        ],
        innerStroke: NSColor.white.withAlphaComponent(0.10),
        shadowColor: NSColor.black.withAlphaComponent(0.42),
        loadingDotsColor: NSColor(red: 0.00, green: 1.0, blue: 0.62, alpha: 0.94),
        orientationAccentColor: NSColor(red: 0.00, green: 1.0, blue: 0.62, alpha: 0.72),
        glowColor: NSColor(red: 0.00, green: 1.0, blue: 0.62, alpha: 0.12),
        pointerColor: NSColor(red: 0.06, green: 0.08, blue: 0.07, alpha: 0.84),
        useVFX: false,
        vfxMaterial: .hudWindow
    )

    // ── Light ─────────────────────────────────────
    static let light = ResolvedPalette(
        bubbleFill: NSColor(red: 0.98, green: 0.99, blue: 1.00, alpha: 0.94),
        bubbleFillAlt: NSColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 0.86),
        textColor: NSColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 0.97),
        badgeTextColor: NSColor(red: 0.18, green: 0.28, blue: 0.50, alpha: 0.94),
        badgeBgColor: NSColor(red: 0.23, green: 0.48, blue: 0.96, alpha: 0.12),
        badgeBorderColor: NSColor(red: 0.23, green: 0.48, blue: 0.96, alpha: 0.30),
        bubbleBorderGradient: [
            NSColor(white: 0.88, alpha: 0.64),
            NSColor(white: 0.95, alpha: 0.40),
            NSColor(red: 0.28, green: 0.50, blue: 0.96, alpha: 0.24),
        ],
        innerStroke: NSColor.white.withAlphaComponent(0.68),
        shadowColor: NSColor.black.withAlphaComponent(0.12),
        loadingDotsColor: NSColor(red: 0.24, green: 0.45, blue: 0.92, alpha: 0.86),
        orientationAccentColor: NSColor(red: 0.24, green: 0.45, blue: 0.92, alpha: 0.54),
        glowColor: NSColor(red: 0.24, green: 0.45, blue: 0.92, alpha: 0.08),
        pointerColor: NSColor(red: 0.97, green: 0.98, blue: 1.00, alpha: 0.92),
        useVFX: false,
        vfxMaterial: .popover
    )

    // ── Liquid Glass ──────────────────────────────
    static func liquidGlass(for appearance: NSAppearance) -> ResolvedPalette {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return ResolvedPalette(
                bubbleFill: NSColor(white: 0.02, alpha: 0.14),
                bubbleFillAlt: NSColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 0.10),
                textColor: NSColor.white.withAlphaComponent(0.96),
                badgeTextColor: NSColor.white.withAlphaComponent(0.92),
                badgeBgColor: NSColor.white.withAlphaComponent(0.14),
                badgeBorderColor: NSColor.white.withAlphaComponent(0.32),
                bubbleBorderGradient: [
                    NSColor.white.withAlphaComponent(0.46),
                    NSColor.white.withAlphaComponent(0.20),
                    NSColor.white.withAlphaComponent(0.14),
                ],
                innerStroke: NSColor.white.withAlphaComponent(0.20),
                shadowColor: NSColor.black.withAlphaComponent(0.28),
                loadingDotsColor: NSColor.white.withAlphaComponent(0.90),
                orientationAccentColor: NSColor.white.withAlphaComponent(0.58),
                glowColor: NSColor.white.withAlphaComponent(0.10),
                pointerColor: NSColor(white: 0.03, alpha: 0.18),
                useVFX: true,
                vfxMaterial: .popover
            )
        }

        return ResolvedPalette(
            bubbleFill: NSColor.white.withAlphaComponent(0.17),
            bubbleFillAlt: NSColor.white.withAlphaComponent(0.10),
            textColor: NSColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 0.94),
            badgeTextColor: NSColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 0.86),
            badgeBgColor: NSColor.white.withAlphaComponent(0.30),
            badgeBorderColor: NSColor.white.withAlphaComponent(0.44),
            bubbleBorderGradient: [
                NSColor.white.withAlphaComponent(0.72),
                NSColor.white.withAlphaComponent(0.46),
                NSColor.black.withAlphaComponent(0.10),
            ],
            innerStroke: NSColor.white.withAlphaComponent(0.36),
            shadowColor: NSColor.black.withAlphaComponent(0.18),
            loadingDotsColor: NSColor.black.withAlphaComponent(0.72),
            orientationAccentColor: NSColor.black.withAlphaComponent(0.34),
            glowColor: NSColor.white.withAlphaComponent(0.10),
            pointerColor: NSColor.white.withAlphaComponent(0.20),
            useVFX: true,
            vfxMaterial: .popover
        )
    }

    static func resolve(_ preset: OverlayThemePreset, appearance: NSAppearance) -> ResolvedPalette {
        switch preset {
        case .darkChrome:  return .darkChrome
        case .light:       return .light
        case .liquidGlass: return .liquidGlass(for: appearance)
        }
    }
}

// MARK: - Content View

/// AppKit view that draws suggestion text + Tab badge with optional multiline wrapping,
/// glassmorphism background, chrome borders, animated loading dots, and directional pointer.
final class SuggestionPanelContentView: NSView {

    // MARK: - Public Properties

    var suggestion: String = "" { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var suggestions: [String] = [] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var selectedIndex: Int = 0 { didSet { needsDisplay = true } }
    var isLoading: Bool = false {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
            isLoading ? startLoadingAnimation() : stopLoadingAnimation()
        }
    }
    var isWrapped: Bool = false { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var verticalOrientation: SuggestionBubbleVerticalOrientation = .below { didSet { needsDisplay = true } }
    var presentationStyle: SuggestionPresentationStyle = .bubble { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var maxTextWidth: CGFloat = 400 { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var maxWrappedTextHeight: CGFloat = 320 { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var themePreset: OverlayThemePreset = .darkChrome { didSet { applyTheme(); needsDisplay = true } }
    var onSuggestionClicked: ((Int) -> Void)?
    var onSelectionCycleRequested: ((Int) -> Void)?

    // MARK: - Fonts & Metrics

    private let textFont = NSFont(name: "Inter", size: 18) ?? NSFont.systemFont(ofSize: 18, weight: .semibold)
    private let badgeFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    private let hSpacing: CGFloat = 7
    private let loadingSpacing: CGFloat = 5
    private let hPad: CGFloat = 14
    private let vPad: CGFloat = 8
    private let badgeHPad: CGFloat = 7
    private let badgeVPad: CGFloat = 3
    private let cornerRadius: CGFloat = 14
    private let pointerSize: CGFloat = 7
    private let glowRadius: CGFloat = 18
    private let rowGap: CGFloat = 8
    private let rowInnerHPad: CGFloat = 10
    private let rowInnerVPad: CGFloat = 8
    private let optionBadgeDiameter: CGFloat = 22

    // MARK: - Loading Animation

    private var loadingPhase: CGFloat = 0
    private var loadingTimer: Timer?

    // MARK: - VFX backing

    private var vfxView: NSVisualEffectView?

    // MARK: - Palette (resolved from preset)

    private var palette: ResolvedPalette = .darkChrome
    private var lastRenderedOptionRects: [NSRect] = []

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        loadingTimer?.invalidate()
        loadingTimer = nil
    }

    // MARK: - Theme

    private func applyTheme() {
        palette = ResolvedPalette.resolve(themePreset, appearance: effectiveAppearance)
        configureVFXBacking()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
        needsDisplay = true
    }

    private func configureVFXBacking() {
        if palette.useVFX {
            if vfxView == nil {
                let v = NSVisualEffectView()
                v.blendingMode = .behindWindow
                v.state = .active
                v.wantsLayer = true
                v.layer?.cornerRadius = cornerRadius
                v.layer?.masksToBounds = true
                addSubview(v, positioned: .below, relativeTo: nil)
                vfxView = v
            }
            vfxView?.material = palette.vfxMaterial
            vfxView?.alphaValue = 0.56
            vfxView?.isEmphasized = true
            vfxView?.isHidden = false
        } else {
            vfxView?.isHidden = true
        }
    }

    override func layout() {
        super.layout()
        vfxView?.frame = bounds
    }

    // MARK: - Loading Animation

    private func startLoadingAnimation() {
        guard loadingTimer == nil else { return }
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.loadingPhase += 0.045
            self.needsDisplay = true
        }
    }

    private func stopLoadingAnimation() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        loadingPhase = 0
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: NSSize {
        if usesPaletteLayout {
            return paletteIntrinsicContentSize()
        }
        let tl = textLayout()
        let loading = loadingIndicatorSize()
        let badge = badgeSize()
        let contentWidth = tl.width + (isLoading ? (loadingSpacing + loading.width) : 0) + contentSpacing + badge.width
        let contentHeight = max(tl.height, badge.height)
        return NSSize(
            width: ceil(contentWidth + contentHorizontalPadding * 2),
            height: ceil(contentHeight + contentVerticalPadding * 2)
        )
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()

        if usesInlineGhostStyle {
            drawInlineGhostContent()
            ctx.restoreGraphicsState()
            return
        }

        let bubbleRect = bounds.insetBy(dx: 1.0, dy: 1.0)

        // ── Outer glow aura ─────────────────────────
        ctx.cgContext.saveGState()
        ctx.cgContext.setShadow(offset: .zero, blur: glowRadius, color: palette.glowColor.cgColor)
        NSColor.clear.setFill()
        let glowPath = NSBezierPath(roundedRect: bubbleRect, xRadius: cornerRadius, yRadius: cornerRadius)
        palette.glowColor.setFill()
        glowPath.fill()
        ctx.cgContext.restoreGState()

        // ── Drop shadow ─────────────────────────────
        ctx.cgContext.saveGState()
        ctx.cgContext.setShadow(offset: CGSize(width: 0, height: -3), blur: 16, color: palette.shadowColor.cgColor)
        let shadowFill = palette.useVFX
            ? palette.bubbleFill.withAlphaComponent(0.14)
            : palette.bubbleFill.withAlphaComponent(max(0.18, palette.bubbleFill.alphaComponent * 0.55))
        shadowFill.setFill()
        let shadowPath = NSBezierPath(roundedRect: bubbleRect, xRadius: cornerRadius, yRadius: cornerRadius)
        shadowPath.fill()
        ctx.cgContext.restoreGState()

        // ── Bubble fill (gradient) ──────────────────
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: cornerRadius, yRadius: cornerRadius)
        let bubbleGradient = NSGradient(colors: [palette.bubbleFill, palette.bubbleFillAlt])
        bubbleGradient?.draw(in: bubblePath, angle: 15)

        // ── Chrome metallic gradient border ─────────
        drawChromeBorder(in: bubbleRect)

        // ── Inner highlight stroke ──────────────────
        let innerRect = bubbleRect.insetBy(dx: 1.4, dy: 1.4)
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
        palette.innerStroke.setStroke()
        innerPath.lineWidth = 0.6
        innerPath.stroke()

        // ── Orientation accent bar ──────────────────
        drawOrientationAccent(in: bubbleRect)

        // ── Directional pointer arrow ───────────────
        drawPointerArrow(in: bubbleRect)

        // ── Content ─────────────────────────────────
        if usesPaletteLayout {
            drawPaletteContent(in: bubbleRect)
            ctx.restoreGraphicsState()
            return
        }

        let tl = textLayout()
        let badge = badgeSize()
        let contentHeight = max(tl.height, badge.height)
        let contentMinY = contentVerticalPadding
        let contentMaxY = contentMinY + contentHeight

        // Text
        let textY: CGFloat = isWrapped ? (contentMaxY - tl.height) : (contentMinY + (contentHeight - tl.height) * 0.5)
        let textRect = CGRect(x: contentHorizontalPadding, y: textY, width: tl.width, height: tl.height)

        let textShadow = NSShadow()
        textShadow.shadowColor = palette.shadowColor
        textShadow.shadowOffset = NSSize(width: 0, height: -1)
        textShadow.shadowBlurRadius = 4

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = isWrapped ? .byWordWrapping : .byTruncatingTail
        if isWrapped { paragraphStyle.lineSpacing = 2.2 }

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: palette.textColor,
            .shadow: textShadow,
            .paragraphStyle: paragraphStyle,
        ]
        (displayText as NSString).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin],
            attributes: textAttrs
        )

        // Loading dots (animated pulse)
        var trailingX = contentHorizontalPadding + tl.width
        if isLoading {
            trailingX = drawAnimatedLoadingDots(
                at: trailingX,
                contentMinY: contentMinY,
                contentHeight: contentHeight,
                textRect: textRect,
                shadow: textShadow
            )
        }

        // Badge
        let badgeX = trailingX + contentSpacing
        let badgeY: CGFloat = isWrapped ? (contentMaxY - badge.height) : (contentMinY + (contentHeight - badge.height) * 0.5)
        drawChromeBadge(at: CGPoint(x: badgeX, y: badgeY), size: badge)

        ctx.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        guard usesPaletteLayout else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        if let index = lastRenderedOptionRects.firstIndex(where: { $0.contains(point) }) {
            onSuggestionClicked?(index)
            return
        }

        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard usesPaletteLayout else {
            super.scrollWheel(with: event)
            return
        }

        let dominantDelta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY
            : event.scrollingDeltaX
        guard abs(dominantDelta) >= 0.5 else {
            super.scrollWheel(with: event)
            return
        }

        onSelectionCycleRequested?(dominantDelta < 0 ? 1 : -1)
    }

    // MARK: - Chrome Border

    private func drawChromeBorder(in bubbleRect: NSRect) {
        let borderPath = NSBezierPath(roundedRect: bubbleRect, xRadius: cornerRadius, yRadius: cornerRadius)
        let colors = palette.bubbleBorderGradient
        guard colors.count >= 2 else { return }
        let gradient = NSGradient(colors: colors)
        NSGraphicsContext.current?.cgContext.saveGState()
        borderPath.setClip()
        borderPath.lineWidth = 1.2
        gradient?.draw(in: bubbleRect, angle: 135)
        NSGraphicsContext.current?.cgContext.restoreGState()

        // Re-stroke on top
        let strokePath = NSBezierPath(roundedRect: bubbleRect, xRadius: cornerRadius, yRadius: cornerRadius)
        gradient?.draw(in: strokePath, angle: 135)
        // Manual gradient stroke simulation
        for (i, color) in colors.enumerated() {
            let frac = CGFloat(i) / CGFloat(max(1, colors.count - 1))
            color.withAlphaComponent(color.alphaComponent * (1.0 - frac * 0.3)).setStroke()
        }
        colors.last?.setStroke()
        strokePath.lineWidth = 1.2
        strokePath.stroke()
    }

    // MARK: - Pointer Arrow

    private func drawPointerArrow(in bubbleRect: NSRect) {
        guard verticalOrientation != .inline else { return }
        let arrowW: CGFloat = 12
        let arrowH: CGFloat = pointerSize
        let arrowX = bubbleRect.minX + 22

        let arrow = NSBezierPath()
        if verticalOrientation == .below {
            // Arrow points UP (toward cursor which is above)
            let baseY = bubbleRect.maxY
            arrow.move(to: NSPoint(x: arrowX, y: baseY))
            arrow.line(to: NSPoint(x: arrowX + arrowW / 2, y: baseY + arrowH))
            arrow.line(to: NSPoint(x: arrowX + arrowW, y: baseY))
            arrow.close()
        } else {
            // Arrow points DOWN (toward cursor which is below)
            let baseY = bubbleRect.minY
            arrow.move(to: NSPoint(x: arrowX, y: baseY))
            arrow.line(to: NSPoint(x: arrowX + arrowW / 2, y: baseY - arrowH))
            arrow.line(to: NSPoint(x: arrowX + arrowW, y: baseY))
            arrow.close()
        }
        palette.pointerColor.setFill()
        arrow.fill()
        palette.bubbleBorderGradient.last?.setStroke()
        arrow.lineWidth = 0.8
        arrow.stroke()
    }

    // MARK: - Animated Loading Dots

    private func drawAnimatedLoadingDots(
        at startX: CGFloat,
        contentMinY: CGFloat,
        contentHeight: CGFloat,
        textRect: CGRect,
        shadow: NSShadow
    ) -> CGFloat {
        let dotRadius: CGFloat = 3.2
        let spacing: CGFloat = 6.0
        let dotCount = 3
        let totalWidth = CGFloat(dotCount) * dotRadius * 2 + CGFloat(dotCount - 1) * spacing

        let dotsX = startX + loadingSpacing
        let dotsY: CGFloat = isWrapped
            ? (textRect.maxY - dotRadius * 2)
            : (contentMinY + (contentHeight - dotRadius * 2) * 0.5)

        for i in 0..<dotCount {
            let phase = loadingPhase - Double(i) * 0.22
            let pulse = (sin(phase * 4.5) + 1.0) / 2.0  // 0..1
            let alpha = 0.35 + pulse * 0.65
            let scale = 0.7 + pulse * 0.3

            let x = dotsX + CGFloat(i) * (dotRadius * 2 + spacing)
            let center = NSPoint(x: x + dotRadius, y: dotsY + dotRadius)
            let r = dotRadius * scale

            let dotColor = palette.loadingDotsColor.withAlphaComponent(alpha)

            // Glow
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.setShadow(
                offset: .zero,
                blur: 6,
                color: dotColor.withAlphaComponent(alpha * 0.5).cgColor
            )
            dotColor.setFill()
            let dotPath = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            dotPath.fill()
            NSGraphicsContext.current?.cgContext.restoreGState()
        }

        return dotsX + totalWidth
    }

    // MARK: - Chrome Badge

    private func drawChromeBadge(at origin: CGPoint, size: NSSize) {
        let badgeRect = CGRect(origin: origin, size: size)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: size.height / 2, yRadius: size.height / 2)

        // Metallic gradient fill
        let fillGradient = NSGradient(colors: [
            badgeFillColor,
            badgeFillColor.withAlphaComponent(badgeFillColor.alphaComponent * 0.6),
        ])
        fillGradient?.draw(in: badgePath, angle: 90)

        // Border
        badgeBorderColor.setStroke()
        badgePath.lineWidth = usesInlineGhostStyle ? 0.6 : 0.8
        badgePath.stroke()

        // Text
        let badgeTextAttrs: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: badgeTextColor,
        ]
        let badgeTextSize = ("Tab" as NSString).size(withAttributes: badgeTextAttrs)
        let textOrigin = CGPoint(
            x: origin.x + (size.width - badgeTextSize.width) * 0.5,
            y: origin.y + (size.height - badgeTextSize.height) * 0.5
        )
        ("Tab" as NSString).draw(at: textOrigin, withAttributes: badgeTextAttrs)
    }

    // MARK: - Orientation Accent

    private func drawOrientationAccent(in bubbleRect: NSRect) {
        guard verticalOrientation != .inline else { return }
        let width: CGFloat = 28
        let height: CGFloat = 3
        let accentX = bubbleRect.minX + 14
        let accentY: CGFloat = (verticalOrientation == .below)
            ? (bubbleRect.maxY - height - 3)
            : (bubbleRect.minY + 3)
        let accentRect = NSRect(x: accentX, y: accentY, width: width, height: height)
        let path = NSBezierPath(roundedRect: accentRect, xRadius: height / 2, yRadius: height / 2)
        palette.orientationAccentColor.setFill()
        path.fill()
    }

    // MARK: - Helpers

    private var displayText: String {
        normalizedDisplayText(suggestion)
    }

    private var displaySuggestions: [String] {
        let source = suggestions.isEmpty ? [suggestion] : suggestions
        let normalized = source
            .map(normalizedDisplayText(_:))
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? ["…"] : normalized
    }

    private var usesPaletteLayout: Bool {
        displaySuggestions.count > 1
    }

    private var usesInlineGhostStyle: Bool {
        presentationStyle == .inlineGhost && !usesPaletteLayout
    }

    private var contentHorizontalPadding: CGFloat {
        usesInlineGhostStyle ? 2 : hPad
    }

    private var contentVerticalPadding: CGFloat {
        usesInlineGhostStyle ? 2 : vPad
    }

    private var contentSpacing: CGFloat {
        usesInlineGhostStyle ? 4 : hSpacing
    }

    private var badgeTextColor: NSColor {
        usesInlineGhostStyle
            ? palette.badgeTextColor.withAlphaComponent(0.78)
            : palette.badgeTextColor
    }

    private var badgeFillColor: NSColor {
        usesInlineGhostStyle
            ? palette.badgeBgColor.withAlphaComponent(max(0.08, palette.badgeBgColor.alphaComponent * 0.55))
            : palette.badgeBgColor
    }

    private var badgeBorderColor: NSColor {
        usesInlineGhostStyle
            ? palette.badgeBorderColor.withAlphaComponent(0.22)
            : palette.badgeBorderColor
    }

    private func drawInlineGhostContent() {
        let tl = textLayout()
        let badge = badgeSize()
        let contentHeight = max(tl.height, badge.height)
        let contentMinY = contentVerticalPadding
        let contentMaxY = contentMinY + contentHeight
        let textY = contentMinY + (contentHeight - tl.height) * 0.5
        let textRect = CGRect(x: contentHorizontalPadding, y: textY, width: tl.width, height: tl.height)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: palette.textColor.withAlphaComponent(0.44),
            .paragraphStyle: paragraphStyle,
        ]
        (displayText as NSString).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin],
            attributes: textAttrs
        )

        var trailingX = contentHorizontalPadding + tl.width
        if isLoading {
            trailingX = drawAnimatedLoadingDots(
                at: trailingX,
                contentMinY: contentMinY,
                contentHeight: contentHeight,
                textRect: textRect,
                shadow: NSShadow()
            )
        }

        let badgeX = trailingX + contentSpacing
        let badgeY = contentMaxY - badge.height - max(0, (contentHeight - badge.height) * 0.5)
        drawChromeBadge(at: CGPoint(x: badgeX, y: badgeY), size: badge)
    }

    private func normalizedDisplayText(_ value: String) -> String {
        let allowedControls: Set<UInt32> = [9, 10, 13]
        let filteredScalars = value.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) || allowedControls.contains(scalar.value)
        }
        let normalized = String(String.UnicodeScalarView(filteredScalars))
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return "…"
        }
        return normalized
    }

    private func paletteIntrinsicContentSize() -> NSSize {
        let layout = paletteLayout(in: NSRect(origin: .zero, size: NSSize(width: maxTextWidth + 80, height: maxWrappedTextHeight)))
        return NSSize(
            width: ceil(layout.contentWidth + hPad * 2),
            height: ceil(layout.contentHeight + vPad * 2)
        )
    }

    private func drawPaletteContent(in bubbleRect: NSRect) {
        let layout = paletteLayout(in: bubbleRect)
        lastRenderedOptionRects = layout.optionRects

        for (index, optionRect) in layout.optionRects.enumerated() {
            let isSelected = index == min(max(0, selectedIndex), displaySuggestions.count - 1)
            drawPaletteOption(
                text: displaySuggestions[index],
                index: index,
                rect: optionRect,
                isSelected: isSelected
            )
        }

        if isLoading {
            _ = drawAnimatedLoadingDots(
                at: bubbleRect.maxX - hPad - loadingIndicatorSize().width - 4,
                contentMinY: bubbleRect.maxY - 20,
                contentHeight: 12,
                textRect: CGRect(x: bubbleRect.maxX - 80, y: bubbleRect.maxY - 22, width: 60, height: 12),
                shadow: NSShadow()
            )
        }
    }

    private func drawPaletteOption(text: String, index: Int, rect: NSRect, isSelected: Bool) {
        let optionPath = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)
        let fillColor = isSelected
            ? palette.badgeBgColor.withAlphaComponent(0.28)
            : NSColor.white.withAlphaComponent(palette.useVFX ? 0.04 : 0.06)
        let borderColor = isSelected
            ? palette.badgeBorderColor.withAlphaComponent(0.88)
            : palette.innerStroke.withAlphaComponent(0.45)
        fillColor.setFill()
        optionPath.fill()
        borderColor.setStroke()
        optionPath.lineWidth = isSelected ? 1.0 : 0.7
        optionPath.stroke()

        let badgeRect = NSRect(
            x: rect.minX + rowInnerHPad,
            y: rect.midY - optionBadgeDiameter * 0.5,
            width: optionBadgeDiameter,
            height: optionBadgeDiameter
        )
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: optionBadgeDiameter * 0.5, yRadius: optionBadgeDiameter * 0.5)
        let badgeFill = isSelected
            ? palette.badgeBgColor.withAlphaComponent(0.55)
            : palette.badgeBgColor.withAlphaComponent(0.22)
        badgeFill.setFill()
        badgePath.fill()
        palette.badgeBorderColor.withAlphaComponent(isSelected ? 0.95 : 0.55).setStroke()
        badgePath.lineWidth = 0.8
        badgePath.stroke()

        let badgeTitle = "\(index + 1)" as NSString
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: palette.badgeTextColor
        ]
        let badgeTitleSize = badgeTitle.size(withAttributes: badgeAttributes)
        badgeTitle.draw(
            at: NSPoint(
                x: badgeRect.midX - badgeTitleSize.width * 0.5,
                y: badgeRect.midY - badgeTitleSize.height * 0.5
            ),
            withAttributes: badgeAttributes
        )

        let textRect = NSRect(
            x: badgeRect.maxX + 10,
            y: rect.minY + rowInnerVPad,
            width: rect.width - (badgeRect.maxX - rect.minX) - rowInnerHPad - 10,
            height: rect.height - rowInnerVPad * 2
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 2
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: isSelected ? palette.textColor : palette.textColor.withAlphaComponent(0.92),
            .paragraphStyle: paragraphStyle
        ]
        (text as NSString).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttrs
        )
    }

    private func paletteLayout(in bubbleRect: NSRect) -> (optionRects: [NSRect], contentWidth: CGFloat, contentHeight: CGFloat) {
        let rowTextWidth = max(240, min(maxTextWidth, bubbleRect.width - (hPad * 2) - optionBadgeDiameter - rowInnerHPad * 2 - 18))
        var optionRects: [NSRect] = []
        var currentY = bubbleRect.maxY - vPad
        let rowWidth = rowTextWidth + optionBadgeDiameter + rowInnerHPad * 2 + 18

        for text in displaySuggestions {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.lineSpacing = 2
            let measured = (text as NSString).boundingRect(
                with: CGSize(width: rowTextWidth, height: maxWrappedTextHeight),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: textFont,
                    .paragraphStyle: paragraphStyle,
                ]
            )
            let rowHeight = max(optionBadgeDiameter + rowInnerVPad * 2, ceil(measured.height) + rowInnerVPad * 2)
            let rect = NSRect(
                x: bubbleRect.minX + hPad,
                y: currentY - rowHeight,
                width: rowWidth,
                height: rowHeight
            )
            optionRects.append(rect)
            currentY = rect.minY - rowGap
        }

        let contentHeight: CGFloat
        if let first = optionRects.first, let last = optionRects.last {
            contentHeight = first.maxY - last.minY
        } else {
            contentHeight = 44
        }

        return (optionRects, rowWidth, contentHeight)
    }

    private func textLayout() -> (width: CGFloat, height: CGFloat) {
        let text = displayText as NSString
        let lineHeight = ceil(textFont.ascender - textFont.descender + textFont.leading)
        if !isWrapped {
            let fullWidth = ceil(text.size(withAttributes: [.font: textFont]).width)
            return (max(48, min(fullWidth, maxTextWidth)), lineHeight)
        }

        let wrappedWidth = max(220, maxTextWidth)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 2.2
        let measured = text.boundingRect(
            with: CGSize(width: wrappedWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: textFont,
                .paragraphStyle: paragraphStyle,
            ],
            context: nil
        )
        let cappedHeight = min(ceil(measured.height), max(lineHeight, maxWrappedTextHeight))
        return (wrappedWidth, max(lineHeight, cappedHeight))
    }

    private func loadingIndicatorSize() -> NSSize {
        guard isLoading else { return .zero }
        // Animated dots
        let dotRadius: CGFloat = 3.2
        let spacing: CGFloat = 6.0
        let dotCount: CGFloat = 3
        let w = dotCount * dotRadius * 2 + (dotCount - 1) * spacing
        return NSSize(width: w, height: dotRadius * 2)
    }

    private func badgeSize() -> NSSize {
        let textSize = ("Tab" as NSString).size(withAttributes: [.font: badgeFont])
        return NSSize(
            width: ceil(textSize.width) + (usesInlineGhostStyle ? 5 : badgeHPad) * 2,
            height: ceil(textSize.height) + (usesInlineGhostStyle ? 2 : badgeVPad) * 2
        )
    }
}
