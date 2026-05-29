import Foundation

/// Table editing commands exposed on the editor. These find the table containing
/// the caret, apply a `TableEditor` mutation to its markdown source, and replace
/// the table's range — keeping the source canonical.
public extension PulpEditorProtocol {
    /// Insert a blank table at the caret. Defaults to a 3-column, 2-row table.
    func insertTable(rows: Int = 2, columns: Int = 3) {
        let sel = selectedRange
        let nsText = text as NSString
        guard sel.location <= nsText.length else { return }

        // Insert on its own line: prefix a newline if not at line start, suffix one.
        let lineStart = nsText.lineRange(for: NSRange(location: sel.location, length: 0)).location
        let atLineStart = sel.location == lineStart
        let prefix = atLineStart ? "" : "\n"
        let table = TableEditor.template(rows: rows, columns: columns)
        let insertText = "\(prefix)\(table)\n"

        applyRemoteEdit(TextEdit(range: sel, replacementText: insertText))
        // Place caret in the first header cell.
        let firstCellOffset = sel.location + prefix.count + 2 // after "| "
        selectedRange = NSRange(location: firstCellOffset, length: 0)
    }

    func insertTableRowBelow() {
        mutateTableAtCaret { md, ctx in TableEditor.insertRow(in: md, afterDataRowIndex: ctx.dataRowIndex) }
    }

    func insertTableRowAbove() {
        mutateTableAtCaret { md, ctx in TableEditor.insertRow(in: md, afterDataRowIndex: ctx.dataRowIndex - 1) }
    }

    func insertTableColumnRight() {
        mutateTableAtCaret { md, ctx in TableEditor.insertColumn(in: md, afterColumnIndex: ctx.columnIndex) }
    }

    func insertTableColumnLeft() {
        mutateTableAtCaret { md, ctx in TableEditor.insertColumn(in: md, afterColumnIndex: ctx.columnIndex - 1) }
    }

    func deleteTableRow() {
        mutateTableAtCaret { md, ctx in TableEditor.deleteRow(in: md, dataRowIndex: ctx.dataRowIndex) }
    }

    func deleteTableColumn() {
        mutateTableAtCaret { md, ctx in TableEditor.deleteColumn(in: md, columnIndex: ctx.columnIndex) }
    }
}

/// A reference to a specific table cell in the document. `rowIndex` is -1 for the
/// header row, 0+ for data rows.
public struct TableCellRef: Equatable {
    public let tableRange: NSRange
    public let rowIndex: Int
    public let columnIndex: Int

    public init(tableRange: NSRange, rowIndex: Int, columnIndex: Int) {
        self.tableRange = tableRange
        self.rowIndex = rowIndex
        self.columnIndex = columnIndex
    }
}

/// Context describing where the caret sits within a table.
public struct TableCaretContext {
    /// Range of the whole table in the document.
    public let tableRange: NSRange
    /// Zero-based data-row index (-1 if caret is in the header row).
    public let dataRowIndex: Int
    /// Zero-based column index under the caret.
    public let columnIndex: Int
    public let isInHeader: Bool
}

/// One row of a table, classified by kind, as seen by the caret resolver.
private struct TableRowToken {
    let token: MarkdownToken
    let isHeader: Bool
    let isSeparator: Bool
}

/// The table row the caret sits in, plus its data-row index (-1 for header).
private struct CaretRow {
    let token: MarkdownToken
    let isHeader: Bool
    let dataRowIndex: Int
}

public extension PulpEditorProtocol {
    /// Resolve which table / row / column the caret is in, if any.
    func tableCaretContext() -> TableCaretContext? {
        let nsText = text as NSString
        let caret = selectedRange.location
        guard caret <= nsText.length else { return nil }

        let tokens = MarkdownTokenizer().tokenize(text)
        guard let table = tokens.first(where: {
            if case .table = $0.type { return NSLocationInRange(caret, $0.range) }
            return false
        }) else { return nil }

        let rowTokens = tableRowTokens(in: tokens, table: table)
        guard let row = caretRow(in: rowTokens, caret: caret) else {
            return TableCaretContext(tableRange: table.range, dataRowIndex: -1, columnIndex: 0, isInHeader: false)
        }

        return TableCaretContext(
            tableRange: table.range,
            dataRowIndex: row.dataRowIndex,
            columnIndex: columnIndex(in: row.token, caret: caret, nsText: nsText),
            isInHeader: row.isHeader
        )
    }

    /// Collect the header / separator / data row tokens that belong to `table`.
    private func tableRowTokens(in tokens: [MarkdownToken], table: MarkdownToken) -> [TableRowToken] {
        tokens.compactMap { token in
            guard NSIntersectionRange(token.range, table.range).length > 0 else { return nil }
            switch token.type {
            case .tableHeaderRow: return TableRowToken(token: token, isHeader: true, isSeparator: false)
            case .tableSeparatorRow: return TableRowToken(token: token, isHeader: false, isSeparator: true)
            case .tableDataRow: return TableRowToken(token: token, isHeader: false, isSeparator: false)
            default: return nil
            }
        }
    }

    /// Find the row containing the caret and its data-row index (-1 for header).
    private func caretRow(in rowTokens: [TableRowToken], caret: Int) -> CaretRow? {
        var dataCounter = 0
        for entry in rowTokens where !entry.isSeparator {
            let end = entry.token.range.location + entry.token.range.length
            if NSLocationInRange(caret, entry.token.range) || caret == end {
                return CaretRow(
                    token: entry.token,
                    isHeader: entry.isHeader,
                    dataRowIndex: entry.isHeader ? -1 : dataCounter
                )
            }
            if !entry.isHeader { dataCounter += 1 }
        }
        return nil
    }

    /// Column index = number of pipes before the caret within the row.
    private func columnIndex(in rowToken: MarkdownToken, caret: Int, nsText: NSString) -> Int {
        let rowText = nsText.substring(with: rowToken.range) as NSString
        let offsetInRow = caret - rowToken.range.location
        var pipes = 0
        for i in 0 ..< min(offsetInRow, rowText.length) where rowText.character(at: i) == 0x7C {
            pipes += 1
        }
        return max(0, pipes - 1)
    }

    /// Resolve the table context to act on: the clicked/active cell if present
    /// (the in-cell editing model never moves the caret), otherwise the caret.
    func resolvedTableContext() -> TableCaretContext? {
        if let cell = activeTableCell {
            return TableCaretContext(
                tableRange: cell.tableRange,
                dataRowIndex: cell.rowIndex,
                columnIndex: cell.columnIndex,
                isInHeader: cell.rowIndex < 0
            )
        }
        return tableCaretContext()
    }

    private func mutateTableAtCaret(_ mutate: (String, TableCaretContext) -> String) {
        guard let ctx = resolvedTableContext() else { return }
        let nsText = text as NSString
        guard NSMaxRange(ctx.tableRange) <= nsText.length else { return }
        let tableMarkdown = nsText.substring(with: ctx.tableRange)
        let newMarkdown = mutate(tableMarkdown, ctx)
        guard newMarkdown != tableMarkdown else { return }
        applyRemoteEdit(TextEdit(range: ctx.tableRange, replacementText: newMarkdown))
    }
}
