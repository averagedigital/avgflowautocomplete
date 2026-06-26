import Foundation

enum LanguageDetect {
    static func detect(from text: String, fallback: String = "en") -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallback
        }

        let cyrillic = trimmed.unicodeScalars.filter(isCyrillic).count
        let latin = trimmed.unicodeScalars.filter(isLatin).count

        if cyrillic > latin {
            return "ru"
        }
        if latin > cyrillic {
            return "en"
        }
        return fallback
    }

    private static func isLatin(_ scalar: UnicodeScalar) -> Bool {
        (65 ... 90).contains(scalar.value) || (97 ... 122).contains(scalar.value)
    }

    private static func isCyrillic(_ scalar: UnicodeScalar) -> Bool {
        (0x0400 ... 0x04FF).contains(scalar.value) || (0x0500 ... 0x052F).contains(scalar.value)
    }
}
