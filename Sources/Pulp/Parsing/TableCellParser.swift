import Foundation

public enum TableCellParser {
    public static func parseCells(from rowContent: String) -> [String] {
        let trimmed = rowContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return [] }

        let inner = String(trimmed.dropFirst().dropLast())
        return inner.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    public static func measureColumnWidths(
        rows: [[String]],
        font: PulpFont,
        padding: CGFloat = 24
    ) -> [CGFloat] {
        guard let first = rows.first else { return [] }
        let columnCount = first.count
        var widths = [CGFloat](repeating: 0, count: columnCount)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        for row in rows {
            for (col, cell) in row.enumerated() where col < columnCount {
                let size = (cell as NSString).size(withAttributes: attrs)
                widths[col] = max(widths[col], size.width + padding)
            }
        }

        return widths
    }
}
