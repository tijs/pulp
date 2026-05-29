import Foundation

/// Pure functions that rewrite GFM table markdown source. Each takes a table's
/// markdown string and returns the mutated markdown. Structural editing (add/remove
/// rows and columns) happens here so the source stays canonical for CRDT sync.
public enum TableEditor {
    /// A blank GFM table template with the given dimensions (excluding the header
    /// separator row). `columns` header cells, one separator row, `rows` data rows.
    public static func template(rows: Int, columns: Int) -> String {
        let cols = max(1, columns)
        let dataRows = max(0, rows)

        let header = "| " + (1 ... cols).map { "Column \($0)" }.joined(separator: " | ") + " |"
        let separator = "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |"
        var lines = [header, separator]
        for _ in 0 ..< dataRows {
            lines.append("| " + Array(repeating: " ", count: cols).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// Parsed representation of a table: header cells, alignment row, data rows.
    struct ParsedTable {
        var header: [String]
        var alignments: [String]
        var rows: [[String]]

        var columnCount: Int {
            header.count
        }
    }

    static func parse(_ markdown: String) -> ParsedTable? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count >= 2 else { return nil }

        let header = cells(from: lines[0])
        let alignments = cells(from: lines[1])
        guard !header.isEmpty else { return nil }

        let rows = lines.dropFirst(2).map { cells(from: $0) }
        return ParsedTable(header: header, alignments: alignments, rows: Array(rows))
    }

    static func render(_ table: ParsedTable) -> String {
        var lines = [row(table.header), row(table.alignments)]
        for dataRow in table.rows {
            lines.append(row(dataRow))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Row operations

    /// Insert a blank data row. `afterDataRowIndex` is the zero-based index among
    /// data rows; pass -1 to insert as the first data row (right after the header).
    public static func insertRow(in markdown: String, afterDataRowIndex index: Int) -> String {
        guard var table = parse(markdown) else { return markdown }
        let blank = Array(repeating: "", count: table.columnCount)
        let insertAt = min(max(0, index + 1), table.rows.count)
        table.rows.insert(blank, at: insertAt)
        return render(table)
    }

    public static func deleteRow(in markdown: String, dataRowIndex index: Int) -> String {
        guard var table = parse(markdown), table.rows.indices.contains(index) else { return markdown }
        table.rows.remove(at: index)
        return render(table)
    }

    // MARK: - Column operations

    public static func insertColumn(in markdown: String, afterColumnIndex index: Int) -> String {
        guard var table = parse(markdown) else { return markdown }
        let insertAt = min(max(0, index + 1), table.columnCount)
        table.header.insert("Column", at: insertAt)
        table.alignments.insert("---", at: min(insertAt, table.alignments.count))
        for i in table.rows.indices {
            let at = min(insertAt, table.rows[i].count)
            table.rows[i].insert("", at: at)
        }
        return render(table)
    }

    public static func deleteColumn(in markdown: String, columnIndex index: Int) -> String {
        guard var table = parse(markdown), table.header.indices.contains(index), table.columnCount > 1 else {
            return markdown
        }
        table.header.remove(at: index)
        if table.alignments.indices.contains(index) { table.alignments.remove(at: index) }
        for i in table.rows.indices where table.rows[i].indices.contains(index) {
            table.rows[i].remove(at: index)
        }
        return render(table)
    }

    // MARK: - Cell content

    /// Set a cell's text. `rowIndex` -1 targets the header; 0+ targets data rows.
    public static func setCell(in markdown: String, rowIndex: Int, columnIndex: Int, value: String) -> String {
        guard var table = parse(markdown) else { return markdown }
        let clean = value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")

        if rowIndex < 0 {
            guard table.header.indices.contains(columnIndex) else { return markdown }
            table.header[columnIndex] = clean
        } else {
            guard table.rows.indices.contains(rowIndex),
                  table.rows[rowIndex].indices.contains(columnIndex) else { return markdown }
            table.rows[rowIndex][columnIndex] = clean
        }
        return render(table)
    }

    /// Read a cell's text. `rowIndex` -1 reads the header.
    public static func cell(in markdown: String, rowIndex: Int, columnIndex: Int) -> String? {
        guard let table = parse(markdown) else { return nil }
        if rowIndex < 0 {
            return table.header.indices.contains(columnIndex) ? table.header[columnIndex] : nil
        }
        guard table.rows.indices.contains(rowIndex),
              table.rows[rowIndex].indices.contains(columnIndex) else { return nil }
        return table.rows[rowIndex][columnIndex]
    }

    // MARK: - Helpers

    private static func cells(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return [] }
        let inner = trimmed.dropFirst().dropLast(trimmed.hasSuffix("|") ? 1 : 0)
        return inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func row(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }
}
