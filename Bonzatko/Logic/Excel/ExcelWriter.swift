import Foundation
import libxlsxwriter

enum ExcelWriterError: LocalizedError {
    case cannotWrite(String)

    var errorDescription: String? {
        switch self {
        case .cannotWrite(let detail): "Soubor Excelu se nepodařilo zapsat (\(detail))."
        }
    }
}

/// Writes the lesson workbook with libxlsxwriter.
enum ExcelWriter {
    /// Row fills driven by conditional formatting on the "Stav" column.
    static let presentFill: lxw_color_t = 0xBDD7EE
    static let absentFill: lxw_color_t = 0xF4B6B6

    static func write(_ data: LessonExportData, to url: URL) throws {
        guard let workbook = workbook_new(url.path) else {
            throw ExcelWriterError.cannotWrite("nelze vytvořit sešit")
        }
        // C strings kept alive until the workbook is closed.
        var cStrings: [UnsafeMutablePointer<CChar>] = []
        defer { cStrings.forEach { free($0) } }
        func cString(_ text: String) -> UnsafePointer<CChar> {
            let pointer = strdup(text)!
            cStrings.append(pointer)
            return UnsafePointer(pointer)
        }

        let header = workbook_add_format(workbook)
        format_set_bold(header)
        format_set_bottom(header, UInt8(LXW_BORDER_THIN.rawValue))
        let presentFormat = workbook_add_format(workbook)
        format_set_bg_color(presentFormat, presentFill)
        let absentFormat = workbook_add_format(workbook)
        format_set_bg_color(absentFormat, absentFill)

        // Sheet 1 – Hodina
        let lessonSheet = workbook_add_worksheet(workbook, LessonExportData.lessonSheetName)
        for (column, title) in LessonExportData.lessonHeaders.enumerated() {
            worksheet_write_string(lessonSheet, 0, lxw_col_t(column), title, header)
        }
        for (index, row) in data.lessonRows.enumerated() {
            let excelRow = lxw_row_t(index + 1)
            worksheet_write_string(lessonSheet, excelRow, 0, row.name, nil)
            if row.status != .empty {
                worksheet_write_string(lessonSheet, excelRow, 1, row.status.rawValue, nil)
            }
            worksheet_write_string(lessonSheet, excelRow, 2, row.studentID.uuidString, nil)
        }
        worksheet_set_column(lessonSheet, 0, 0, 34, nil)
        worksheet_set_column(lessonSheet, 1, 1, 16, nil)
        var hidden = lxw_row_col_options(hidden: 1, level: 0, collapsed: 0)
        worksheet_set_column_opt(lessonSheet, 2, 2, 38, nil, &hidden)
        worksheet_freeze_panes(lessonSheet, 1, 0)

        if !data.lessonRows.isEmpty {
            let lastRow = lxw_row_t(data.lessonRows.count)

            // Drop-down list with the allowed values; an empty cell is allowed too.
            var list: [UnsafePointer<CChar>?] = [cString(ExcelStatus.present.rawValue), cString(ExcelStatus.absent.rawValue), nil]
            try list.withUnsafeMutableBufferPointer { buffer in
                var validation = lxw_data_validation()
                validation.validate = UInt8(LXW_VALIDATION_TYPE_LIST.rawValue)
                validation.value_list = buffer.baseAddress
                validation.ignore_blank = UInt8(LXW_VALIDATION_ON.rawValue)
                validation.error_type = UInt8(LXW_VALIDATION_ERROR_TYPE_STOP.rawValue)
                validation.error_title = cString("Neplatný stav")
                validation.error_message = cString("Vyberte „přítomen“, „nepřítomen“, nebo buňku nechte prázdnou.")
                let result = worksheet_data_validation_range(lessonSheet, 1, 1, lastRow, 1, &validation)
                guard result == LXW_NO_ERROR else { throw ExcelWriterError.cannotWrite("ověření dat") }
            }

            // Whole row coloured by the status in column B; changes as soon as the cell is edited in Excel.
            for (status, format) in [(ExcelStatus.present, presentFormat), (ExcelStatus.absent, absentFormat)] {
                var conditional = lxw_conditional_format()
                conditional.type = UInt8(LXW_CONDITIONAL_TYPE_FORMULA.rawValue)
                conditional.value_string = cString("=$B2=\"\(status.rawValue)\"")
                conditional.format = format
                let result = worksheet_conditional_format_range(lessonSheet, 1, 0, lastRow, 2, &conditional)
                guard result == LXW_NO_ERROR else { throw ExcelWriterError.cannotWrite("podmíněné formátování") }
            }
        }

        // Sheet 2 – Souhrn
        let summarySheet = workbook_add_worksheet(workbook, LessonExportData.summarySheetName)
        for (column, title) in LessonExportData.summaryHeaders.enumerated() {
            worksheet_write_string(summarySheet, 0, lxw_col_t(column), title, header)
        }
        for (index, row) in data.summaryRows.enumerated() {
            let excelRow = lxw_row_t(index + 1)
            worksheet_write_string(summarySheet, excelRow, 0, row.name, nil)
            worksheet_write_number(summarySheet, excelRow, 1, Double(row.present), nil)
            worksheet_write_number(summarySheet, excelRow, 2, Double(row.absent), nil)
            worksheet_write_number(summarySheet, excelRow, 3, Double(row.total), nil)
            if !row.note.isEmpty {
                worksheet_write_string(summarySheet, excelRow, 4, row.note, nil)
            }
        }
        worksheet_set_column(summarySheet, 0, 0, 34, nil)
        worksheet_set_column(summarySheet, 1, 3, 18, nil)
        worksheet_set_column(summarySheet, 4, 4, 22, nil)
        worksheet_freeze_panes(summarySheet, 1, 0)

        let result = workbook_close(workbook)
        guard result == LXW_NO_ERROR else {
            throw ExcelWriterError.cannotWrite(String(cString: lxw_strerror(result)))
        }
    }
}
