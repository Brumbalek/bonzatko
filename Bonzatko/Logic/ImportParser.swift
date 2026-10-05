import CoreXLSX
import Foundation
import ZIPFoundation

/// A grid of cell texts read from .xlsx or .csv.
struct ImportTable: Hashable, Sendable {
    var sheetName: String
    var rows: [[String]]

    var columnCount: Int { rows.map(\.count).max() ?? 0 }

    func cell(_ row: Int, _ column: Int) -> String {
        column < rows[row].count ? rows[row][column] : ""
    }
}

enum ImportError: LocalizedError, Equatable {
    case unreadableText
    case invalidDocx
    case invalidXlsx
    case unsupportedFile(String)

    var errorDescription: String? {
        switch self {
        case .unreadableText: "Soubor se nepodařilo přečíst jako text."
        case .invalidDocx: "Soubor .docx je poškozený nebo to není dokument Wordu."
        case .invalidXlsx: "Soubor .xlsx je poškozený nebo to není sešit Excelu."
        case .unsupportedFile(let ext): "Soubory typu .\(ext) nelze importovat. Použijte .txt, .docx, .xlsx nebo .csv."
        }
    }
}

enum ImportParser {
    enum Source: Sendable {
        case names([String])
        case tables([ImportTable])
    }

    static func read(url: URL) throws -> Source {
        switch url.pathExtension.lowercased() {
        case "txt", "text": return .names(names(fromText: try decodeText(Data(contentsOf: url))))
        case "docx": return .names(names(fromText: try docxText(url: url)))
        case "csv": return .tables([ImportTable(sheetName: url.deletingPathExtension().lastPathComponent,
                                                rows: csvRows(try decodeText(Data(contentsOf: url))))])
        case "xlsx": return .tables(try xlsxTables(url: url))
        case let ext: throw ImportError.unsupportedFile(ext)
        }
    }

    // MARK: Plain text

    /// Every non-empty line is one name; surrounding and repeated spaces are dropped.
    static func names(fromText text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map(Names.clean)
            .filter { !$0.isEmpty }
    }

    /// UTF‑8 (with or without BOM), UTF‑16 with BOM, otherwise Windows‑1250 as used by Czech Windows.
    static func decodeText(_ data: Data) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        }
        if let text = String(data: data, encoding: .windowsCP1250) {
            return text
        }
        throw ImportError.unreadableText
    }

    // MARK: Word

    /// Text of all paragraphs (including those inside table cells), one paragraph per line.
    static func docxText(url: URL) throws -> String {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ImportError.invalidDocx
        }
        guard let entry = archive["word/document.xml"] else { throw ImportError.invalidDocx }
        var xml = Data()
        do {
            _ = try archive.extract(entry, skipCRC32: true) { xml.append($0) }
        } catch {
            throw ImportError.invalidDocx
        }
        return try docxText(documentXML: xml)
    }

    static func docxText(documentXML: Data) throws -> String {
        let collector = DocxTextCollector()
        let parser = XMLParser(data: documentXML)
        parser.delegate = collector
        guard parser.parse() else { throw ImportError.invalidDocx }
        return collector.lines.joined(separator: "\n")
    }

    private final class DocxTextCollector: NSObject, XMLParserDelegate {
        var lines: [String] = []
        private var current = ""
        private var inText = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "w:t": inText = true
            case "w:tab": current += " "
            case "w:br", "w:cr": finishLine()
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "w:t": inText = false
            case "w:p": finishLine()
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { current += string }
        }

        private func finishLine() {
            lines.append(current)
            current = ""
        }
    }

    // MARK: CSV

    /// Parses CSV with quoted fields. The delimiter (";", "," or tab) is detected from the first line.
    static func csvRows(_ text: String) -> [[String]] {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let delimiter: Character = [";", "\t", ","].max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ";"

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = iterator.next()

        while let char = pending {
            pending = iterator.next()
            if inQuotes {
                if char == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == delimiter {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r" || char == "\r\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { $0.contains { !Names.clean($0).isEmpty } }
    }

    // MARK: Excel

    static func xlsxTables(url: URL) throws -> [ImportTable] {
        guard let file = XLSXFile(filepath: url.path) else { throw ImportError.invalidXlsx }
        do {
            let sharedStrings = try file.parseSharedStrings()
            var tables: [ImportTable] = []
            for workbook in try file.parseWorkbooks() {
                for (name, path) in try file.parseWorksheetPathsAndNames(workbook: workbook) {
                    let worksheet = try file.parseWorksheet(at: path)
                    let rows = gridRows(worksheet: worksheet, sharedStrings: sharedStrings)
                    tables.append(ImportTable(sheetName: name ?? "List \(tables.count + 1)", rows: rows))
                }
            }
            return tables
        } catch {
            throw ImportError.invalidXlsx
        }
    }

    private static func gridRows(worksheet: Worksheet, sharedStrings: SharedStrings?) -> [[String]] {
        var rows: [[String]] = []
        for row in worksheet.data?.rows ?? [] {
            var values: [String] = []
            for cell in row.cells {
                let column = columnIndex(cell.reference.column.value)
                if values.count <= column {
                    values.append(contentsOf: Array(repeating: "", count: column - values.count + 1))
                }
                values[column] = text(of: cell, sharedStrings: sharedStrings)
            }
            if values.contains(where: { !Names.clean($0).isEmpty }) {
                rows.append(values)
            }
        }
        return rows
    }

    private static func text(of cell: Cell, sharedStrings: SharedStrings?) -> String {
        if cell.type == .sharedString {
            guard let sharedStrings, let index = cell.value.flatMap(Int.init), sharedStrings.items.indices.contains(index) else {
                return ""
            }
            let item = sharedStrings.items[index]
            return item.text ?? item.richText.compactMap(\.text).joined()
        }
        if let inline = cell.inlineString?.text {
            return inline
        }
        return cell.value ?? ""
    }

    /// "A" → 0, "Z" → 25, "AA" → 26 …
    static func columnIndex(_ letters: String) -> Int {
        letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    static func columnLetters(_ index: Int) -> String {
        var number = index + 1
        var letters = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            number = (number - 1) / 26
        }
        return letters
    }

    /// Joins the selected columns with a space, in the order they were selected.
    static func names(from table: ImportTable, columns: [Int], skipFirstRow: Bool) -> [String] {
        table.rows.indices.dropFirst(skipFirstRow ? 1 : 0).compactMap { rowIndex in
            let name = Names.clean(columns.map { table.cell(rowIndex, $0) }.joined(separator: " "))
            return name.isEmpty ? nil : name
        }
    }
}
