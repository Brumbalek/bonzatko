import Foundation

enum Czech {
    /// Picks the right plural form: 1 student, 2–4 studenti, 0 / 5+ studentů.
    static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        switch count {
        case 1: "\(count) \(one)"
        case 2...4: "\(count) \(few)"
        default: "\(count) \(many)"
        }
    }

    static func students(_ count: Int) -> String {
        plural(count, one: "student", few: "studenti", many: "studentů")
    }

    static func names(_ count: Int) -> String {
        plural(count, one: "jméno", few: "jména", many: "jmen")
    }
}
