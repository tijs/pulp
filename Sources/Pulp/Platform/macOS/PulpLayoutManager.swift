#if canImport(AppKit)
import AppKit

class PulpLayoutManager: NSLayoutManager {
    var tableRanges: [NSRange] = []
    var tableDrawingData: [NSRange: TableDrawingData] = [:]

    struct TableDrawingData {
        let columnWidths: [CGFloat]
        let rows: [TableRow]
        let headerRow: TableRow?
        let font: NSFont
        let headerFont: NSFont
        let borderColor: NSColor
        let textColor: NSColor
        let secondaryTextColor: NSColor
    }

    struct TableRow {
        let cells: [String]
        let characterRange: NSRange
        let isHeader: Bool
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        var tablesToDraw = [(NSRange, TableDrawingData)]()

        var pos = glyphsToShow.location
        let end = glyphsToShow.location + glyphsToShow.length

        while pos < end {
            var isInTable = false
            for tableRange in tableRanges {
                let tableGlyphRange = glyphRange(forCharacterRange: tableRange, actualCharacterRange: nil)
                let overlap = NSIntersectionRange(NSRange(location: pos, length: end - pos), tableGlyphRange)
                if overlap.length > 0 {
                    if pos < tableGlyphRange.location {
                        let beforeRange = NSRange(location: pos, length: tableGlyphRange.location - pos)
                        super.drawGlyphs(forGlyphRange: beforeRange, at: origin)
                    }

                    if let data = tableDrawingData[tableRange] {
                        tablesToDraw.append((tableRange, data))
                    }

                    pos = tableGlyphRange.location + tableGlyphRange.length
                    isInTable = true
                    break
                }
            }

            if !isInTable {
                let chunk = NSRange(location: pos, length: end - pos)
                super.drawGlyphs(forGlyphRange: chunk, at: origin)
                pos = end
            }
        }

        for (tableRange, data) in tablesToDraw {
            drawTable(tableRange: tableRange, data: data, at: origin)
        }
    }

    private func drawTable(tableRange: NSRange, data: TableDrawingData, at origin: NSPoint) {
        guard let textContainer = textContainers.first else { return }

        let tableGlyphRange = glyphRange(forCharacterRange: tableRange, actualCharacterRange: nil)
        var tableRect = boundingRect(forGlyphRange: tableGlyphRange, in: textContainer)
        tableRect.origin.x = origin.x
        tableRect.origin.y += origin.y

        let totalWidth = data.columnWidths.reduce(0, +)
        guard totalWidth > 0 else { return }

        let availableWidth = textContainer.containerSize.width - textContainer.lineFragmentPadding * 2
        let scale = availableWidth / totalWidth
        let tableLeft = origin.x + textContainer.lineFragmentPadding
        let tableWidth = availableWidth

        let rowHeight: CGFloat = data.font.pointSize * 2.2
        let headerHeight: CGFloat = data.headerFont.pointSize * 2.2
        let totalRows = data.rows.count
        let tableHeight = headerHeight + CGFloat(max(0, totalRows - 1)) * rowHeight
        let tableTop = tableRect.origin.y

        let fullTableRect = NSRect(
            x: tableLeft,
            y: tableTop,
            width: tableWidth,
            height: tableHeight
        )

        // Outer border
        data.borderColor.setStroke()
        let border = NSBezierPath(roundedRect: fullTableRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 1
        border.stroke()

        // Draw rows
        var y = tableTop
        for (rowIndex, row) in data.rows.enumerated() {
            let thisRowHeight = rowIndex == 0 && row.isHeader ? headerHeight : rowHeight
            let font = row.isHeader ? data.headerFont : data.font

            // Header bottom border
            if rowIndex == 0, row.isHeader {
                data.secondaryTextColor.withAlphaComponent(0.25).setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: tableLeft, y: y + thisRowHeight))
                line.line(to: NSPoint(x: tableLeft + tableWidth, y: y + thisRowHeight))
                line.lineWidth = 1.5
                line.stroke()
            } else if rowIndex > 0 {
                data.borderColor.setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: tableLeft + 1, y: y))
                line.line(to: NSPoint(x: tableLeft + tableWidth - 1, y: y))
                line.lineWidth = 0.5
                line.stroke()
            }

            // Draw cells
            var x = tableLeft
            for (colIndex, cell) in row.cells.enumerated() {
                let colWidth = colIndex < data.columnWidths.count
                    ? data.columnWidths[colIndex] * scale
                    : 0

                let cellRect = NSRect(x: x + 8, y: y + (thisRowHeight - font.pointSize) / 2 - 2, width: colWidth - 16, height: font.pointSize + 4)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: data.textColor,
                ]
                (cell as NSString).draw(in: cellRect, withAttributes: attrs)

                x += colWidth
            }

            y += thisRowHeight
        }

        // Vertical column lines
        data.borderColor.setStroke()
        var colX = tableLeft
        for (i, width) in data.columnWidths.enumerated() {
            colX += width * scale
            if i < data.columnWidths.count - 1 {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: colX, y: tableTop + 1))
                line.line(to: NSPoint(x: colX, y: tableTop + tableHeight - 1))
                line.lineWidth = 0.5
                line.stroke()
            }
        }
    }
}
#endif
