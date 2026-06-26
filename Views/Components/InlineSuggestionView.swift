import SwiftUI

struct InlineSuggestionView: View {
    let text: String
    var onAccept: (() -> Void)?

    var body: some View {
        if !text.isEmpty {
            HStack {
                Text(text)
                    .font(.body.italic())
                    .foregroundStyle(AITheme.accentMint.opacity(0.92))
                    .lineLimit(2)

                Spacer(minLength: AITheme.spacingS)

                Text("Tab")
                    .font(AITheme.fontCaption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AITheme.buttonRadius, style: .continuous))
            .onTapGesture {
                onAccept?()
            }
            .accessibilityLabel(L.isRussian ? "Подсказка: \(text)" : "Suggestion: \(text)")
            .accessibilityHint(L.isRussian ? "Нажмите или Tab чтобы принять" : "Tap or press Tab to accept")
        }
    }
}
