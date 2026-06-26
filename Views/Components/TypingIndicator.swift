import SwiftUI

struct TypingIndicator: View {
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if reduceMotion {
                // Static accessible indicator when Reduce Motion is ON
                ProgressView()
                    .controlSize(.small)
                    .tint(AITheme.accent)
            } else {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(AITheme.accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: AITheme.accent.opacity(0.6), radius: phase ? 4 : 0)
                        .opacity(phase ? 1.0 : 0.3)
                        .scaleEffect(phase ? 1.1 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: phase
                        )
                }
            }
        }
        .padding(.horizontal, AITheme.spacingM)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: Capsule())
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(AITheme.innerGlow, lineWidth: 0.5)
        )
        .shadow(
            color: AITheme.shadowLight.color,
            radius: AITheme.shadowLight.radius,
            x: AITheme.shadowLight.x,
            y: AITheme.shadowLight.y
        )
        .onAppear {
            if !reduceMotion {
                phase = true
            }
        }
        .accessibilityLabel(L.isRussian ? "Загрузка подсказки" : "Loading suggestion")
    }
}
