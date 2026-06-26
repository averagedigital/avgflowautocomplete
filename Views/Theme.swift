import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// AIComplete Design System — v3.0 Chrome
// Dark theme · Chrome/Metal accents · Glassmorphism
// 8pt grid · WCAG 2.2 AA · Reduce Motion/Transparency aware
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum AITheme {

    // ── Spacing (8pt grid) ────────────────────────────────────
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // ── Liquid Chromium Palette (aligned with site) ───────────
    static let bgBase = Color(red: 0.024, green: 0.035, blue: 0.031)          // #060908
    static let bgSurface = Color(red: 0.051, green: 0.078, blue: 0.067)       // #0d1411
    static let bgSurfaceElevated = Color(red: 0.051, green: 0.078, blue: 0.067).opacity(0.72)

    static let accentMint = Color(red: 0.0, green: 1.0, blue: 0.615)          // #00ff9d
    static let accentGlow = Color(red: 0.0, green: 1.0, blue: 0.615).opacity(0.15)
    static let liquidChromeBase = Color(red: 0.886, green: 0.910, blue: 0.941) // #e2e8f0
    static let borderSubtle = Color.white.opacity(0.08)
    static let borderHover = Color(red: 0.0, green: 1.0, blue: 0.615).opacity(0.30)

    // Compatibility aliases
    static let chromeSilver  = liquidChromeBase
    static let chromeWhite   = Color.white.opacity(0.95)
    static let chromeDark    = bgSurface
    static let chromeDeep    = bgBase
    static let chromeBlue    = Color(red: 0.337, green: 0.612, blue: 0.839)   // #569CD6

    // ── Legacy / Warm Complements (kept for overlay compatibility) ──
    static let accentLight = Color(hue: 0.30, saturation: 0.22, brightness: 0.96)
    static let accentDeep  = Color(hue: 0.0, saturation: 0.0, brightness: 0.60)
    static let peach       = Color(hue: 0.07, saturation: 0.28, brightness: 0.98)
    static let lavender    = Color(hue: 0.72, saturation: 0.14, brightness: 0.94)

    // MARK: - Native Colors (system-aware, dark mode compatible)

    static let accent = accentMint
    static let accentMist = accentMint.opacity(0.10)
    static let cream = chromeDark
    static let darkMist = chromeDeep

    // Semantic Backgrounds
    static let windowBg    = bgBase
    static let cardBg      = bgSurface
    static let sectionTint = borderSubtle
    static let separator   = borderSubtle

    // ── Text (WCAG-safe) ─────────────────────────────────────
    static let textPrimary   = Color(red: 0.953, green: 0.957, blue: 0.965)   // #f3f4f6
    static let textSecondary = Color(red: 0.545, green: 0.604, blue: 0.580)   // #8b9a94
    static let textTertiary  = Color(red: 0.545, green: 0.604, blue: 0.580).opacity(0.72)

    // ── Overlay ───────────────────────────────────────────────
    static let overlayBg     = chromeDark
    static let overlayBorder = borderSubtle
    static let overlayShadow = Color.black.opacity(0.4)

    // ── Gradients ─────────────────────────────────────────────
    /// Main background: transparent — relies on window vibrancy
    static let backgroundGradient = LinearGradient(
        colors: [bgBase, bgSurface],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Chrome metallic gradient for headers & accents
    static let accentGradient = LinearGradient(
        colors: [liquidChromeBase, chromeWhite, accentMint.opacity(0.88)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Chrome shimmer for decorative elements
    static let chromeGradient = LinearGradient(
        colors: [
            liquidChromeBase.opacity(0.90),
            chromeWhite.opacity(0.75),
            chromeBlue.opacity(0.52),
            accentMint.opacity(0.38),
            Color.white.opacity(0.22)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let chatBotGradient = LinearGradient(
        colors: [accentMint.opacity(0.08), liquidChromeBase.opacity(0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [Color.white.opacity(0.07), bgSurface.opacity(0.44)],
        startPoint: .top,
        endPoint: .bottom
    )

    // ── Premium Effects ───────────────────────────────────────
    static let innerGlow = LinearGradient(
        colors: [.white.opacity(0.15), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Metallic highlight for chrome orbs
    static let metalHighlight = RadialGradient(
        colors: [.white.opacity(0.88), liquidChromeBase.opacity(0.42), accentMint.opacity(0.12), .clear],
        center: .topLeading,
        startRadius: 0,
        endRadius: 80
    )

    // ── Corner Radii ──────────────────────────────────────────
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 12
    static let overlayRadius: CGFloat = 14
    static let inputRadius: CGFloat = 10

    // ── Typography ────────────────────────────────────────────
    static let fontTitleLarge   = Font.custom("Inter", size: 28).weight(.bold)
    static let fontTitleSection = Font.custom("Inter", size: 20).weight(.bold)
    static let fontHeading      = Font.custom("Inter", size: 17).weight(.semibold)
    static let fontBody         = Font.custom("Inter", size: 15)
    static let fontCaption      = Font.custom("Inter", size: 13)
    static let fontCaptionBold  = Font.custom("Inter", size: 13).weight(.semibold)
    static let fontCaption2     = Font.custom("Inter", size: 12)
    static let fontMono         = Font.custom("JetBrains Mono", size: 12)

    // ── Shadows ───────────────────────────────────────────────
    static let shadowLight  = (color: Color.black.opacity(0.25), radius: CGFloat(6), x: CGFloat(0), y: CGFloat(3))
    static let shadowMedium = (color: Color.black.opacity(0.35), radius: CGFloat(10), x: CGFloat(0), y: CGFloat(5))
    static let shadowHover  = (color: Color.black.opacity(0.40), radius: CGFloat(14), x: CGFloat(0), y: CGFloat(7))

    // ── Source Badge Colors ───────────────────────────────────
    static let sourceLocal = accentMint
    static let sourceCloud = chromeBlue
    static let sourceHybrid = Color(red: 0.36, green: 0.86, blue: 0.78)
    static let sourceDict  = Color.orange

    // ── Section Header ────────────────────────────────────────
    static func sectionHeader(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: spacingS) {
            // Chrome accent dot
            ZStack {
                Circle()
                    .fill(borderSubtle)
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(accentGradient)
                    .frame(width: 10, height: 10)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textPrimary)
            }
            Text(text)
                .font(fontHeading)
                .foregroundStyle(textPrimary)
        }
    }

    // ── Status Pill ───────────────────────────────────────────
    static func statusPill(_ text: String, isPositive: Bool) -> some View {
        Text(text)
            .font(fontCaptionBold)
            .padding(.horizontal, 10)
            .padding(.vertical, spacingXS)
            .background(
                Capsule()
                    .fill(isPositive ? accentMint.opacity(0.14) : Color.orange.opacity(0.15))
            )
            .foregroundStyle(isPositive ? accentMint : .orange)
    }

    // ── Source Badge ──────────────────────────────────────────
    static func sourceBadge(source: CompletionSource, model: String? = nil) -> some View {
        HStack(spacing: spacingXS) {
            Circle()
                .fill(sourceColor(for: source))
                .frame(width: 6, height: 6)
            Text(sourceLabel(for: source, model: model))
                .font(fontCaption2.weight(.medium))
                .foregroundStyle(textSecondary)
        }
        .padding(.horizontal, spacingS)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(sourceColor(for: source).opacity(0.1))
        )
    }

    static func sourceColor(for source: CompletionSource) -> Color {
        switch source {
        case .local: return sourceLocal
        case .cloud: return sourceCloud
        case .hybrid: return sourceHybrid
        case .userDictionary: return sourceDict
        }
    }

    static func sourceLabel(for source: CompletionSource, model: String? = nil) -> String {
        switch source {
        case .local: return "local"
        case .cloud:
            if let model { return "cloud·\(model)" }
            return "cloud"
        case .hybrid: return "hybrid"
        case .userDictionary: return "dict"
        }
    }

    // ── Empty State ───────────────────────────────────────────
    static func emptyState(
        icon: String,
        title: String,
        subtitle: String,
        action: String? = nil,
        onAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: spacingM) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(textTertiary)
            Text(title)
                .font(fontHeading)
                .foregroundStyle(textSecondary)
            Text(subtitle)
                .font(fontCaption)
                .foregroundStyle(textTertiary)
                .multilineTextAlignment(.center)
            if let action, let onAction {
                Button(action, action: onAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(spacingL)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Feature Flags
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum FeatureFlags {
    private static let defaults = AppGroupManager.shared.sharedUserDefaults() ?? .standard

    static var showSourceBadge: Bool {
        defaults.object(forKey: "ff.showSourceBadge") as? Bool ?? true
    }
    static var showWhyDisclosure: Bool {
        defaults.object(forKey: "ff.showWhyDisclosure") as? Bool ?? true
    }
    static var showAcceptanceHistory: Bool {
        defaults.object(forKey: "ff.showAcceptanceHistory") as? Bool ?? true
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Accessibility-Aware Animation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct ReduceMotionAware: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let animation: Animation

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: UUID())
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - GlassBackground (Reduce Transparency aware)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Card Style (Motion-aware, Dark Chrome)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct AICardStyle: ViewModifier {
    var tint: Color = Color.clear
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(AITheme.spacingM + 2)
            .background(
                ZStack {
                    // Solid dark card background
                    RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    // Tint overlay
                    tint
                }
                .clipShape(RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous))
                .shadow(
                    color: AITheme.shadowLight.color,
                    radius: isHovering ? AITheme.shadowMedium.radius : AITheme.shadowLight.radius,
                    x: AITheme.shadowLight.x,
                    y: isHovering ? AITheme.shadowMedium.y : AITheme.shadowLight.y
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AITheme.liquidChromeBase.opacity(0.22),
                                AITheme.borderSubtle,
                                AITheme.accentMint.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovering ? 0.9 : 0.5
                    )
            )
            .scaleEffect(isHovering ? 1.008 : 1.0)
            .offset(y: isHovering ? -1 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: isHovering
            )
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Button Styles (Dark Chrome)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct AIAccentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AITheme.fontBody.weight(.semibold))
            .padding(.horizontal, AITheme.spacingM + 4)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? AITheme.accentMint.opacity(0.24)
                            : AITheme.accentMint.opacity(0.14)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous)
                            .stroke(AITheme.accentMint.opacity(0.42), lineWidth: 0.7)
                    )
                    .shadow(color: AITheme.accentGlow, radius: 14, x: 0, y: 4)
            )
            .foregroundStyle(AITheme.textPrimary)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

struct AISecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AITheme.fontBody.weight(.medium))
            .padding(.horizontal, AITheme.spacingM)
            .padding(.vertical, AITheme.spacingS)
            .background(
                RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous)
                    .fill(AITheme.bgSurface.opacity(0.72))
                    .background(
                        RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous)
                            .stroke(AITheme.borderSubtle, lineWidth: 0.6)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous))
            )
            .foregroundStyle(AITheme.textPrimary)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - View Extensions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension View {
    func aiCard(tint: Color = Color.clear) -> some View {
        modifier(AICardStyle(tint: tint))
    }

    func glassBackground() -> some View {
        self.background(
            ZStack {
                GlassBackground(material: .hudWindow, blendingMode: .behindWindow)
                AITheme.windowBg.opacity(0.82)
            }
        )
    }

    /// Apply chrome metallic gradient to text foreground
    func chromeText() -> some View {
        self.foregroundStyle(AITheme.accentGradient)
    }

    /// Apply chrome gradient to title-level text
    func chromeTitleText() -> some View {
        self.foregroundStyle(AITheme.chromeGradient)
    }

    /// Liquid chromium card with metallic gradient background, glow, and hover effects
    func liquidChromiumCard(padding: CGFloat = AITheme.spacingM + 2) -> some View {
        modifier(LiquidChromiumCardModifier(padding: padding))
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Liquid Chromium Card Style
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct LiquidChromiumCardModifier: ViewModifier {
    var padding: CGFloat = AITheme.spacingM + 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                        .fill(AITheme.bgSurfaceElevated)
                    RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AITheme.liquidChromeBase.opacity(0.09),
                                    AITheme.accentMint.opacity(0.05),
                                    Color.black.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Ellipse()
                        .fill(AITheme.accentMint.opacity(0.10))
                        .frame(width: 220, height: 80)
                        .blur(radius: 18)
                        .offset(x: -70, y: -56)
                }
                .shadow(
                    color: AITheme.shadowLight.color,
                    radius: isHovering ? AITheme.shadowMedium.radius : AITheme.shadowLight.radius,
                    x: AITheme.shadowLight.x,
                    y: isHovering ? AITheme.shadowMedium.y : AITheme.shadowLight.y
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AITheme.cardRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AITheme.liquidChromeBase.opacity(0.30),
                                AITheme.borderSubtle,
                                AITheme.accentMint.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovering ? 1.0 : 0.8
                    )
            )
            .scaleEffect(isHovering ? 1.006 : 1.0)
            .offset(y: isHovering ? -1 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: isHovering
            )
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
