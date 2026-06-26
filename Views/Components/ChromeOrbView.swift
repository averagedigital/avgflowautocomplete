import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Chrome Orb — Procedural metallic decoration
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Abstract chrome/metal orb for decorative use.
/// Renders a reflective metallic sphere with animated shimmer.
struct ChromeOrbView: View {
    var size: CGFloat = 80
    var shimmer: Bool = true

    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            // Base sphere — dark metallic
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            AITheme.chromeSilver.opacity(0.7),
                            AITheme.chromeBlue.opacity(0.35),
                            AITheme.chromeDark
                        ],
                        center: UnitPoint(x: 0.35, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )

            // Top-left highlight (specular)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.1),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.3, y: 0.2),
                        startRadius: 0,
                        endRadius: size * 0.3
                    )
                )
                .frame(width: size * 0.55, height: size * 0.4)
                .offset(x: -size * 0.12, y: -size * 0.18)

            // Bottom reflection
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            AITheme.chromeBlue.opacity(0.25),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.25
                    )
                )
                .frame(width: size * 0.5, height: size * 0.2)
                .offset(y: size * 0.28)

            // Animated shimmer band
            if shimmer {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.20),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size * 0.7, height: size * 0.15)
                    .rotationEffect(.degrees(25))
                    .offset(x: (phase - 0.5) * size * 0.3, y: -size * 0.05)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if shimmer {
                withAnimation(
                    .easeInOut(duration: 4)
                    .repeatForever(autoreverses: true)
                ) {
                    phase = 1
                }
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Chrome Blob — Organic abstract shape
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Free-flowing chrome blob shape, inspired by liquid-metal aesthetics.
struct ChromeBlobView: View {
    var width: CGFloat = 120
    var height: CGFloat = 90
    var variant: Int = 0

    @State private var morphPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Warped ellipse base
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            AITheme.chromeSilver.opacity(0.8),
                            AITheme.chromeBlue.opacity(0.3),
                            AITheme.chromeSilver.opacity(0.5),
                            Color.white.opacity(0.2)
                        ],
                        startPoint: UnitPoint(x: 0.1 + morphPhase * 0.1, y: 0),
                        endPoint: UnitPoint(x: 0.9 - morphPhase * 0.1, y: 1)
                    )
                )
                .frame(width: width, height: height)
                .rotationEffect(.degrees(Double(variant) * 30 + morphPhase * 5))
                .scaleEffect(x: 1.0 + morphPhase * 0.05)

            // Specular highlight
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.7), Color.clear],
                        center: UnitPoint(x: 0.35, y: 0.2),
                        startRadius: 0,
                        endRadius: width * 0.3
                    )
                )
                .frame(width: width * 0.5, height: height * 0.35)
                .offset(x: -width * 0.1, y: -height * 0.15)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 6)
                .repeatForever(autoreverses: true)
            ) {
                morphPhase = 1
            }
        }
    }
}

struct ChromeOrbView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 30) {
            ChromeOrbView(size: 60)
            ChromeOrbView(size: 100)
            ChromeBlobView(width: 120, height: 80, variant: 1)
        }
        .padding(40)
        .background(AITheme.chromeDeep)
    }
}
