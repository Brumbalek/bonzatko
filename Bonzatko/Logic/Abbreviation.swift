import Foundation

/// Builds the short class name used in export file names.
enum Abbreviation {
    static let fallback = "Trida"

    /// One word → the word without diacritics ("Účetnictví" → "Ucetnictvi").
    /// More words → uppercase first letters without diacritics ("Úvod do marketingu" → "UDM").
    static func make(from className: String) -> String {
        let words = className
            .split(whereSeparator: { $0.isWhitespace })
            .map { asciiAlphanumerics(String($0)) }
            .filter { !$0.isEmpty }

        let result: String
        switch words.count {
        case 0: result = fallback
        case 1: result = words[0]
        default: result = words.map { String($0.prefix(1)).uppercased() }.joined()
        }
        return result
    }

    /// Cleans a manually edited abbreviation so it is safe in a file name.
    static func sanitize(_ abbreviation: String) -> String {
        let cleaned = FileNameSanitizer.sanitize(abbreviation)
        return cleaned.isEmpty ? fallback : cleaned
    }

    static func stripDiacritics(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "cs_CZ"))
    }

    private static func asciiAlphanumerics(_ word: String) -> String {
        String(stripDiacritics(word).unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}

/// Replaces characters that are not allowed (or are troublesome) in macOS/Windows file names.
enum FileNameSanitizer {
    private static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)

    static func sanitize(_ name: String) -> String {
        let replaced = String(name.unicodeScalars.map { forbidden.contains($0) ? "_" : Character($0) })
        // Leading dots would hide the file; trailing dots/spaces break on Windows.
        return replaced
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .trimmingCharacters(in: .whitespaces)
    }
}
