#if canImport(AppKit)
import AppKit
import Foundation

// MARK: - Internal Text View (handles custom drawing)

class PulpInternalTextView: NSTextView {
    weak var pulpParent: PulpNSTextView?
    var drawingInfo = DrawingInfo.empty

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        let theme = drawingInfo.theme

        for blockRect in drawingInfo.codeBlockRects where blockRect.intersects(rect) {
            theme.codeBackgroundColor.setFill()
            NSBezierPath(roundedRect: blockRect, xRadius: 8, yRadius: 8).fill()
        }

        // A callout for a leading frontmatter fence (e.g. Kiem's `status:
        // active`): a tinted background plus a colored left accent bar,
        // mirroring how note-taking apps (Bear) render a metadata block —
        // Bear's is a plain blockquote, this achieves the same read for a
        // fence Pulp doesn't otherwise give any visual treatment.
        for blockRect in drawingInfo.frontmatterRects where blockRect.intersects(rect) {
            theme.accentColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: blockRect, xRadius: 8, yRadius: 8).fill()
            theme.accentColor.setFill()
            let accentBar = NSRect(x: blockRect.minX, y: blockRect.minY, width: 3, height: blockRect.height)
            NSBezierPath(roundedRect: accentBar, xRadius: 1.5, yRadius: 1.5).fill()
        }

        for table in drawingInfo.tableInfos where table.backgroundRect.intersects(rect) {
            drawTable(table, in: rect)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let theme = drawingInfo.theme

        for hrRect in drawingInfo.horizontalRuleRects where hrRect.intersects(dirtyRect) {
            theme.secondaryTextColor.withAlphaComponent(0.3).setFill()
            NSRect(x: hrRect.origin.x + 40, y: hrRect.midY, width: hrRect.width - 80, height: 1).fill()
        }

        for bullet in drawingInfo.bulletItems where bullet.rect.intersects(dirtyRect) {
            drawBullet(bullet, theme: theme)
        }

        for item in drawingInfo.checkboxItems where item.rect.intersects(dirtyRect) {
            drawCheckbox(in: item.rect, checked: item.checked, theme: theme)
        }

        if let control = drawingInfo.tableControl, control.buttonRect.intersects(dirtyRect) {
            drawTableControl(control)
        }
    }

    private func drawTableControl(_ control: DrawingInfo.TableControl) {
        let rect = control.buttonRect
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        // Subtle drop shadow so the button reads as a floating control on the cell.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        control.accentColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Three white dots (⋯) to signal a menu.
        NSColor.white.setFill()
        let dotSize: CGFloat = 3
        let gap: CGFloat = 5
        let centerY = rect.midY - dotSize / 2
        for i in -1 ... 1 {
            let dot = NSRect(x: rect.midX + CGFloat(i) * gap - dotSize / 2, y: centerY, width: dotSize, height: dotSize)
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    private func drawTable(_ table: DrawingInfo.TableInfo, in dirtyRect: NSRect) {
        let bg = table.backgroundRect
        let borderColor = table.borderColor
        let totalContentWidth = table.columnWidths.reduce(0, +)
        guard totalContentWidth > 0 else { return }

        let scale = bg.width / totalContentWidth
        let cornerRadius: CGFloat = 6
        let rowHeight = table.rowHeight
        let cellPadding: CGFloat = 14

        /// Uniform row rect: row i spans [bg.minY + i*rowHeight, +rowHeight]
        func rowRect(_ index: Int) -> NSRect {
            NSRect(x: bg.minX, y: bg.minY + CGFloat(index) * rowHeight, width: bg.width, height: rowHeight)
        }

        // Backgrounds (header fill + alternating stripes), clipped to rounded shape
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bg, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
        for (index, row) in table.rows.enumerated() {
            if row.isHeader {
                table.headerBackground.setFill()
                rowRect(index).fill()
            } else if index % 2 == 1 {
                table.rowStripeBackground.setFill()
                rowRect(index).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // Outer border
        borderColor.setStroke()
        let borderPath = NSBezierPath(roundedRect: bg.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        borderPath.lineWidth = 1
        borderPath.stroke()

        // Row dividers + header bottom border + cell content
        for (index, row) in table.rows.enumerated() {
            let rect = rowRect(index)

            if index > 0 {
                let isHeaderDivider = table.rows[index - 1].isHeader
                (isHeaderDivider ? table.strongBorderColor : borderColor).setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: bg.minX + 1, y: rect.minY))
                line.line(to: NSPoint(x: bg.maxX - 1, y: rect.minY))
                line.lineWidth = isHeaderDivider ? 1.5 : 0.5
                line.stroke()
            }

            // Cell content, vertically centered
            let font = row.isHeader ? table.headerFont : table.font
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: table.textColor,
            ]
            let textHeight = font.ascender - font.descender

            var cellX = bg.minX
            for (colIndex, cell) in row.cells.enumerated() {
                let colWidth = colIndex < table.columnWidths.count
                    ? table.columnWidths[colIndex] * scale
                    : 0

                // Skip the cell currently covered by the inline editor.
                let isEditing = table.editingCell.map { $0.displayRow == index && $0.column == colIndex } ?? false
                if !isEditing {
                    let cellTextRect = NSRect(
                        x: cellX + cellPadding,
                        y: rect.minY + (rowHeight - textHeight) / 2,
                        width: max(0, colWidth - cellPadding * 2),
                        height: textHeight
                    )
                    (cell as NSString).draw(in: cellTextRect, withAttributes: attrs)
                }

                cellX += colWidth
            }
        }

        // Vertical column lines
        borderColor.setStroke()
        var colX = bg.minX
        for (i, width) in table.columnWidths.enumerated() {
            colX += width * scale
            if i < table.columnWidths.count - 1 {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: colX, y: bg.minY + 1))
                line.line(to: NSPoint(x: colX, y: bg.maxY - 1))
                line.lineWidth = 0.5
                line.stroke()
            }
        }
    }

    private func drawBullet(_ bullet: DrawingInfo.BulletItem, theme: PulpTheme) {
        theme.accentColor.setFill()
        theme.accentColor.setStroke()
        switch bullet.style {
        case .filledDot:
            NSBezierPath(ovalIn: bullet.rect).fill()
        case .ring:
            // Hollow ring: stroke an inset oval so the line weight stays crisp.
            let ring = NSBezierPath(ovalIn: bullet.rect.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.5
            ring.stroke()
        case .diamond:
            let r = bullet.rect
            let diamond = NSBezierPath()
            diamond.move(to: NSPoint(x: r.midX, y: r.minY))
            diamond.line(to: NSPoint(x: r.maxX, y: r.midY))
            diamond.line(to: NSPoint(x: r.midX, y: r.maxY))
            diamond.line(to: NSPoint(x: r.minX, y: r.midY))
            diamond.close()
            diamond.fill()
        }
    }

    private func drawCheckbox(in rect: NSRect, checked: Bool, theme: PulpTheme) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)

        if checked {
            theme.checkboxTintColor.setFill()
            path.fill()

            let checkmark = NSBezierPath()
            let inset: CGFloat = 3.5
            checkmark.move(to: NSPoint(x: rect.minX + inset, y: rect.midY))
            checkmark.line(to: NSPoint(x: rect.minX + rect.width * 0.4, y: rect.maxY - inset))
            checkmark.line(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
            NSColor.white.setStroke()
            checkmark.lineWidth = 2
            checkmark.lineCapStyle = .round
            checkmark.lineJoinStyle = .round
            checkmark.stroke()
        } else {
            theme.secondaryTextColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let parent = pulpParent
        else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "b":
            parent.toggleBold()
            return true
        case "i":
            parent.toggleItalic()
            return true
        case "k":
            parent.toggleInlineCode()
            return true
        case "1": parent.setHeading(level: 1)
            return true
        case "2": parent.setHeading(level: 2)
            return true
        case "3": parent.setHeading(level: 3)
            return true
        case "4": parent.setHeading(level: 4)
            return true
        case "5": parent.setHeading(level: 5)
            return true
        case "6": parent.setHeading(level: 6)
            return true
        default:
            break
        }

        if event.modifierFlags.contains(.shift) {
            switch event.charactersIgnoringModifiers {
            case "x", "X":
                parent.toggleStrikethrough()
                return true
            case "h", "H":
                parent.toggleHighlight()
                return true
            case "t", "T":
                parent.insertTable()
                return true
            default:
                break
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard let parent = pulpParent else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)

        if let control = drawingInfo.tableControl, control.buttonRect.insetBy(dx: -6, dy: -6).contains(point) {
            // Commit any in-progress cell edit before opening the structural menu.
            parent.commitCellEdit()
            parent.showTableMenu(from: self, at: NSPoint(x: control.buttonRect.midX, y: control.buttonRect.maxY))
            return
        }

        // Click inside a table cell → open the inline cell editor.
        if parent.tableCellHit(at: point) != nil {
            parent.beginEditingCell(at: point)
            return
        }

        for item in drawingInfo.checkboxItems {
            let hitArea = item.rect.insetBy(dx: -4, dy: -4)
            if hitArea.contains(point) {
                if let layoutManager, let textContainer {
                    let textPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
                    let charIndex = layoutManager.characterIndex(
                        for: textPoint,
                        in: textContainer,
                        fractionOfDistanceBetweenInsertionPoints: nil
                    )
                    parent.toggleCheckbox(at: charIndex)
                    return
                }
            }
        }

        // Click landed outside any table cell/control — dismiss table editing.
        parent.endTableEditing()
        super.mouseDown(with: event)
    }

    /// Floating contextual menu: structural table edits when right-clicking inside
    /// a table, otherwise an "Insert Table" entry above the standard text actions.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let parent = pulpParent, isEditable else { return super.menu(for: event) }
        let point = convert(event.locationInWindow, from: nil)

        // Right-click in a cell activates it (control shows) and offers structural
        // edits — without opening the inline editor.
        if parent.activateCell(at: point) {
            return parent.makeTableMenu()
        }

        let menu = super.menu(for: event) ?? NSMenu()
        let insert = NSMenuItem(title: "Insert Table (3×2)", action: #selector(PulpNSTextView.menuInsertTable), keyEquivalent: "")
        insert.target = parent
        menu.insertItem(insert, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }
}

#endif
