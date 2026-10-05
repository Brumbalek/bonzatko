import Foundation
import Testing
import ZIPFoundation
@testable import Bonzatko

/// All names here are fictional.
struct ImportParserTests {
    @Test func textIgnoresEmptyLinesAndExtraSpaces() {
        let text = "  Jan Novák  \n\n\r\nEva   Dvořáková\n   \nPetr Malý\r\n"
        #expect(ImportParser.names(fromText: text) == ["Jan Novák", "Eva Dvořáková", "Petr Malý"])
    }

    @Test func decodesUTF8WithBOMAndWindows1250() throws {
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("Žofie Řeháková".utf8)
        #expect(try ImportParser.decodeText(bom) == "Žofie Řeháková")

        let cp1250 = "Žofie Řeháková".data(using: .windowsCP1250)!
        #expect(try ImportParser.decodeText(cp1250) == "Žofie Řeháková")
    }

    @Test func csvWithSemicolonsAndQuotes() {
        let csv = "Jméno;Příjmení;Poznámka\nJan;Novák;\"má; středník\"\n\"Eva \"\"Evička\"\"\";Dvořáková;\n;;\n"
        let rows = ImportParser.csvRows(csv)
        #expect(rows == [
            ["Jméno", "Příjmení", "Poznámka"],
            ["Jan", "Novák", "má; středník"],
            ["Eva \"Evička\"", "Dvořáková", ""],
        ])
    }

    @Test func csvWithCommas() {
        #expect(ImportParser.csvRows("a,b\r\nc,d") == [["a", "b"], ["c", "d"]])
    }

    @Test func joinsSelectedColumnsInSelectionOrder() {
        let table = ImportTable(sheetName: "List1", rows: [
            ["Příjmení", "Jméno", "E-mail"],
            ["Novák", "Jan", "jan@example.com"],
            ["Dvořáková", "Eva"],
            ["", "", "jen@email.cz"],
        ])
        #expect(ImportParser.names(from: table, columns: [1, 0], skipFirstRow: true) == ["Jan Novák", "Eva Dvořáková"])
        #expect(ImportParser.names(from: table, columns: [0], skipFirstRow: false) == ["Příjmení", "Novák", "Dvořáková"])
    }

    @Test func columnLettersRoundTrip() {
        #expect(ImportParser.columnIndex("A") == 0)
        #expect(ImportParser.columnIndex("Z") == 25)
        #expect(ImportParser.columnIndex("AA") == 26)
        for index in [0, 25, 26, 51, 701, 702] {
            #expect(ImportParser.columnIndex(ImportParser.columnLetters(index)) == index)
        }
    }

    @Test func docxParagraphsAndTableCells() throws {
        let url = try TestFiles.docx(body: """
        <w:p><w:r><w:t>Seznam studentů</w:t></w:r></w:p>
        <w:p/>
        <w:p><w:r><w:t xml:space="preserve">Jan </w:t></w:r><w:r><w:t>Novák</w:t></w:r></w:p>
        <w:tbl>
          <w:tr><w:tc><w:p><w:r><w:t>Eva Dvořáková</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Petr Malý</w:t></w:r></w:p></w:tc></w:tr>
        </w:tbl>
        <w:p><w:r><w:t>   </w:t></w:r></w:p>
        """)
        guard case .names(let names) = try ImportParser.read(url: url) else {
            Issue.record("Expected names")
            return
        }
        #expect(names == ["Seznam studentů", "Jan Novák", "Eva Dvořáková", "Petr Malý"])
    }

    @Test func xlsxWithSharedAndInlineStrings() throws {
        let url = try TestFiles.xlsx(
            sharedStrings: ["Jméno", "Příjmení", "Jan", "Novák"],
            rows: """
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
            <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" t="s"><v>3</v></c></row>
            <row r="4"><c r="B4" t="inlineStr"><is><t>Dvořáková</t></is></c><c r="A4" t="inlineStr"><is><t>Eva</t></is></c></row>
            """
        )
        guard case .tables(let tables) = try ImportParser.read(url: url) else {
            Issue.record("Expected tables")
            return
        }
        #expect(tables.count == 1)
        #expect(tables[0].sheetName == "Studenti")
        #expect(ImportParser.names(from: tables[0], columns: [0, 1], skipFirstRow: true) == ["Jan Novák", "Eva Dvořáková"])
    }

    @Test func rejectsUnsupportedAndBrokenFiles() throws {
        #expect(throws: ImportError.unsupportedFile("pdf")) {
            try ImportParser.read(url: URL(filePath: "/tmp/seznam.pdf"))
        }
        let broken = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).docx")
        try Data("not a zip".utf8).write(to: broken)
        #expect(throws: ImportError.invalidDocx) { try ImportParser.read(url: broken) }
    }
}

struct ImportPlannerTests {
    private let existing = [
        Student(name: "Jan Novák"),
        Student(name: "Eva Dvořáková", removedAt: .now),
    ]

    @Test func detectsConflictsCaseInsensitively() {
        let candidates = [
            ImportCandidate(name: "jan novák"),
            ImportCandidate(name: "Eva Dvořáková"),
            ImportCandidate(name: "Petr Malý"),
            ImportCandidate(name: "Petr  Malý"),
            ImportCandidate(name: "   "),
        ]
        let plan = ImportPlanner.plan(candidates: candidates, existing: existing)
        #expect(plan.map(\.conflict) == [.existingStudent, .removedStudent, .none, .earlierInImport, .none])
        #expect(plan.map(\.finalName) == [nil, nil, "Petr Malý", nil, nil])
    }

    @Test func addsDisambiguatedNames() {
        let candidates = [
            ImportCandidate(name: "Jan Novák", duplicateChoice: .addDisambiguated),
            ImportCandidate(name: "Jan Novák", duplicateChoice: .addDisambiguated),
            ImportCandidate(name: "Eva Dvořáková", duplicateChoice: .addDisambiguated),
        ]
        let plan = ImportPlanner.plan(candidates: candidates, existing: existing)
        #expect(plan.map(\.finalName) == ["Jan Novák (2)", "Jan Novák (3)", "Eva Dvořáková (2)"])
    }
}

@MainActor
struct ClassStoreTests {
    private func makeStore() -> (ClassStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BonzatkoTests-\(UUID())")
        return (ClassStore(repository: ClassRepository(directory: directory)), directory)
    }

    @Test func persistsEveryChangeAndReloads() throws {
        let (store, directory) = makeStore()
        let classID = store.createClass(name: "Úvod do marketingu", abbreviation: "UDM")
        store.addStudents(["Jan Novák", "Eva Dvořáková"], to: classID)
        let jan = try #require(store.schoolClass(classID)?.students.first { $0.name == "Jan Novák" })
        store.renameStudent(jan.id, to: "Jan  Novák ml.", in: classID)
        store.removeStudents([jan.id], from: classID)

        let reloaded = ClassStore(repository: ClassRepository(directory: directory))
        let schoolClass = try #require(reloaded.schoolClass(classID))
        #expect(schoolClass.name == "Úvod do marketingu")
        #expect(schoolClass.activeStudents.map(\.name) == ["Eva Dvořáková"])
        #expect(schoolClass.removedStudents.map(\.name) == ["Jan Novák ml."])
        #expect(schoolClass.removedStudents.first?.id == jan.id)

        reloaded.restoreStudent(jan.id, in: classID)
        #expect(reloaded.schoolClass(classID)?.activeStudents.count == 2)
    }

    @Test func newStudentGetsLowestDrawCountOfActiveStudents() throws {
        let (store, _) = makeStore()
        let classID = store.createClass(name: "Účetnictví", abbreviation: "Ucetnictvi")
        #expect(store.schoolClass(classID)?.virtualDrawCountForNewStudent() == 0)

        var schoolClass = try #require(store.schoolClass(classID))
        let a = Student(name: "Adam Bílý"), b = Student(name: "Bára Černá")
        schoolClass.students = [a, b]
        schoolClass.lessons = [
            Lesson(name: "L1", isClosed: true, draws: [Draw(studentID: a.id, result: .present), Draw(studentID: b.id, result: .absent)]),
            Lesson(name: "L2", draws: [Draw(studentID: a.id, result: .present), Draw(studentID: b.id, result: .skipped)]),
        ]
        // Adam has 2 recorded draws, Bára 1 (the skipped draw does not count).
        #expect(schoolClass.virtualDrawCountForNewStudent() == 1)
    }

    @Test func unreadableFileIsReportedAndLeftAlone() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BonzatkoTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let broken = directory.appending(path: "broken.json")
        try Data("{".utf8).write(to: broken)

        let store = ClassStore(repository: ClassRepository(directory: directory))
        #expect(store.classes.isEmpty)
        #expect(store.errorMessage != nil)
        #expect(try Data(contentsOf: broken) == Data("{".utf8))
    }
}
