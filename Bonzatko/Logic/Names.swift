import Foundation

enum Names {
    static let czech = Locale(identifier: "cs_CZ")

    /// Trims the name and collapses runs of whitespace (incl. non‑breaking spaces) to a single space.
    static func clean(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Key used to detect duplicates: cleaned and case-insensitive (diacritics still matter).
    static func key(_ name: String) -> String {
        clean(name).lowercased(with: czech)
    }

    /// Czech alphabetical order ("ch" after "h", "Č" after "C" …).
    static func czechOrder(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive], range: nil, locale: czech) == .orderedAscending
    }

    static func sortedCzech<T>(_ items: [T], by name: (T) -> String) -> [T] {
        items.sorted { czechOrder(name($0), name($1)) }
    }

    /// "Jan Novák" → "Jan Novák (2)", or the next free number.
    static func disambiguate(_ name: String, takenKeys: Set<String>) -> String {
        let base = clean(name)
        var number = 2
        while takenKeys.contains(key("\(base) (\(number))")) {
            number += 1
        }
        return "\(base) (\(number))"
    }
}
