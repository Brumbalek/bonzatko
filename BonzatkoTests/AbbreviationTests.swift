import Foundation
import Testing
@testable import Bonzatko

struct AbbreviationTests {
    @Test(arguments: [
        ("Účetnictví", "Ucetnictvi"),
        ("Úvod do marketingu", "UDM"),
        ("  Úvod   do  marketingu ", "UDM"),
        ("Marketing", "Marketing"),
        ("Řízení lidských zdrojů", "RLZ"),
        ("Marketing 2", "M2"),
        ("Čeština a literatura", "CAL"),
        ("", "Trida"),
        ("???", "Trida"),
    ])
    func makesAbbreviation(name: String, expected: String) {
        #expect(Abbreviation.make(from: name) == expected)
    }

    @Test func sanitizesManualAbbreviation() {
        #expect(Abbreviation.sanitize("UDM/2") == "UDM_2")
        #expect(Abbreviation.sanitize("  ") == "Trida")
        #expect(Abbreviation.sanitize("Účto") == "Účto")
    }

    @Test(arguments: [
        ("UDM_Hodina261004", "UDM_Hodina261004"),
        ("A/B:C*D?E\"F<G>H|I\\J", "A_B_C_D_E_F_G_H_I_J"),
        ("..skrytý", "skrytý"),
        ("konec. ", "konec"),
        ("řádek\nzlom", "řádek_zlom"),
    ])
    func sanitizesFileNames(input: String, expected: String) {
        #expect(FileNameSanitizer.sanitize(input) == expected)
    }

    @Test func dateStamp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9))!
        #expect(LessonNaming.dateStamp(date, calendar: calendar) == "261004")
    }
}

struct NamesTests {
    @Test func cleansWhitespace() {
        #expect(Names.clean("  Jana \t  Nováková\u{00A0} ") == "Jana Nováková")
    }

    @Test func czechSorting() {
        let sorted = Names.sortedCzech(["Chmelová Eva", "Hrubý Petr", "Čermák Adam", "Cibulka Ivo", "Šťastná Ola", "Sova Jan"]) { $0 }
        #expect(sorted == ["Cibulka Ivo", "Čermák Adam", "Hrubý Petr", "Chmelová Eva", "Sova Jan", "Šťastná Ola"])
    }

    @Test func disambiguatesWithNextFreeNumber() {
        let taken: Set = [Names.key("Jan Novák"), Names.key("Jan Novák (2)")]
        #expect(Names.disambiguate("Jan Novák", takenKeys: taken) == "Jan Novák (3)")
    }

    @Test func czechPlurals() {
        #expect(Czech.students(1) == "1 student")
        #expect(Czech.students(3) == "3 studenti")
        #expect(Czech.students(5) == "5 studentů")
        #expect(Czech.students(0) == "0 studentů")
    }
}
