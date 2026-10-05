import Foundation
import ZIPFoundation

/// Builds minimal .docx and .xlsx files for tests.
enum TestFiles {
    static func docx(body: String) throws -> URL {
        try zip(extension: "docx", entries: [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """,
            "word/document.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)</w:body></w:document>
            """,
        ])
    }

    static func xlsx(sharedStrings: [String], rows: String) throws -> URL {
        let items = sharedStrings.map { "<si><t>\($0)</t></si>" }.joined()
        return try zip(extension: "xlsx", entries: [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
            </Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
            </Relationships>
            """,
            "xl/workbook.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets><sheet name="Studenti" sheetId="1" r:id="rId1"/></sheets>
            </workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
            </Relationships>
            """,
            "xl/sharedStrings.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(sharedStrings.count)" uniqueCount="\(sharedStrings.count)">\(items)</sst>
            """,
            "xl/worksheets/sheet1.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows)</sheetData></worksheet>
            """,
        ])
    }

    private static func zip(extension ext: String, entries: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).\(ext)")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, content) in entries.sorted(by: { $0.key < $1.key }) {
            let data = Data(content.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }
}
