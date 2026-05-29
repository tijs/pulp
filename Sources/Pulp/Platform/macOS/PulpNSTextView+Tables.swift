#if canImport(AppKit)
import AppKit
import Foundation

/// Table rendering geometry, in-cell editing, and structural-edit menus for
/// the macOS editor. Split out of PulpNSTextView to keep that file focused.
extension PulpNSTextView {
    /// The control button is shown for the active cell — the one last clicked (so
    /// it survives after a cell edit commits) or, failing that, the cell the caret
    /// sits in (keyboard navigation). Hidden while the inline editor field is open
    /// (the field covers that cell).
    func tableControlInfo() -> DrawingInfo.TableControl? {
        guard isEditable, cellEditor == nil else { return nil }

        if let cell = activeCell {
            return controlButton(tableRange: cell.tableRange, sourceRow: cell.rowIndex, columnIndex: cell.columnIndex)
        }
        guard let ctx = tableCaretContext() else { return nil }
        let sourceRow = ctx.isInHeader ? -1 : ctx.dataRowIndex
        return controlButton(tableRange: ctx.tableRange, sourceRow: sourceRow, columnIndex: ctx.columnIndex)
    }

    /// Compute the control button rect for a specific cell (sourceRow -1 = header).
    func controlButton(tableRange: NSRange, sourceRow: Int, columnIndex: Int) -> DrawingInfo.TableControl? {
        guard let tableToken = cachedTokens.first(where: {
            if case .table = $0.type { return $0.range == tableRange }
            return false
        }) else { return nil }
        guard let layoutManager = textView.layoutManager, textView.textContainer != nil else { return nil }

        let containerOrigin = textView.textContainerOrigin
        let glyphRange = layoutManager.glyphRange(forCharacterRange: tableToken.range, actualCharacterRange: nil)
        var unionRect = NSRect.zero
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            unionRect = unionRect == .zero ? lineRect : unionRect.union(lineRect)
        }
        guard unionRect != .zero else { return nil }

        let tableLeft = containerOrigin.x
        let tableWidth = textView.bounds.width - containerOrigin.x * 2
        let tableTop = unionRect.origin.y + containerOrigin.y

        let rowDataCount = cachedTokens.filter {
            guard NSIntersectionRange($0.range, tableToken.range).length > 0 else { return false }
            if case .tableHeaderRow = $0.type { return true }
            if case .tableDataRow = $0.type { return true }
            return false
        }.count
        let rowHeight = unionRect.height / CGFloat(max(1, rowDataCount))
        let displayRow = sourceRow < 0 ? 0 : sourceRow + 1

        let columnWidths = tableColumnWidths(for: tableToken)
        let totalWidth = columnWidths.reduce(0, +)
        guard totalWidth > 0 else { return nil }
        let scale = tableWidth / totalWidth

        var cellX = tableLeft
        for i in 0 ..< min(columnIndex, columnWidths.count) {
            cellX += columnWidths[i] * scale
        }
        let colWidth = columnIndex < columnWidths.count ? columnWidths[columnIndex] * scale : 0
        let cellRight = cellX + colWidth
        let cellTop = tableTop + CGFloat(displayRow) * rowHeight

        let buttonSize: CGFloat = 16
        let buttonRect = NSRect(
            x: cellRight - buttonSize - 4,
            y: cellTop + (rowHeight - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )

        return .init(buttonRect: buttonRect, accentColor: theme.accentColor)
    }

    // MARK: - Table Cell Editing

    /// A hit-tested table cell: its source coordinates plus the on-screen rect.
    struct TableCellHit {
        let tableRange: NSRange
        let rowIndex: Int
        let columnIndex: Int
        let cellRect: NSRect
        var ref: TableCellRef {
            TableCellRef(tableRange: tableRange, rowIndex: rowIndex, columnIndex: columnIndex)
        }
    }

    /// Hit-test a point against tables. Returns the source cell coordinates and the
    /// on-screen cell rect, or nil if the point isn't inside a table cell.
    func tableCellHit(at point: NSPoint) -> TableCellHit? {
        for table in textView.drawingInfo.tableInfos {
            let bg = table.backgroundRect
            guard bg.contains(point) else { continue }

            let totalWidth = table.columnWidths.reduce(0, +)
            guard totalWidth > 0 else { return nil }
            let scale = bg.width / totalWidth

            let rowIdx = min(table.rows.count - 1, max(0, Int((point.y - bg.minY) / table.rowHeight)))
            guard table.rows.indices.contains(rowIdx) else { return nil }

            var x = bg.minX
            var colIdx = 0
            var cellRect = NSRect(x: bg.minX, y: bg.minY + CGFloat(rowIdx) * table.rowHeight, width: 0, height: table.rowHeight)
            for (i, width) in table.columnWidths.enumerated() {
                let w = width * scale
                if point.x >= x, point.x < x + w {
                    colIdx = i
                    cellRect.origin.x = x
                    cellRect.size.width = w
                    break
                }
                x += w
                if i == table.columnWidths.count - 1 {
                    colIdx = i
                    cellRect.origin.x = x - w
                    cellRect.size.width = w
                }
            }

            // Map row index to source: header is row 0 in display, -1 in source.
            let sourceRow = table.rows[rowIdx].isHeader ? -1 : displayRowToDataRow(table: table, displayIndex: rowIdx)
            // Need the table token range — find it by matching backgroundRect's tokens.
            guard let tableRange = tableRange(matching: bg) else { return nil }
            return TableCellHit(tableRange: tableRange, rowIndex: sourceRow, columnIndex: colIdx, cellRect: cellRect)
        }
        return nil
    }

    func displayRowToDataRow(table: DrawingInfo.TableInfo, displayIndex: Int) -> Int {
        var dataIdx = -1
        for i in 0 ... displayIndex where !table.rows[i].isHeader {
            dataIdx += 1
        }
        return dataIdx
    }

    func tableRange(matching bgRect: NSRect) -> NSRange? {
        guard let layoutManager = textView.layoutManager, textView.textContainer != nil else { return nil }
        let containerOrigin = textView.textContainerOrigin
        for token in cachedTokens {
            guard case .table = token.type else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil)
            var unionRect = NSRect.zero
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                unionRect = unionRect == .zero ? lineRect : unionRect.union(lineRect)
            }
            let top = unionRect.origin.y + containerOrigin.y
            if abs(top - bgRect.minY) < 2 { return token.range }
        }
        return nil
    }

    /// Open an inline editor over a cell. Does not move the text caret — the cell's
    /// control state is tracked by `activeCell`, so clicks never reflow the table.
    func beginEditingCell(at point: NSPoint) {
        guard let hit = tableCellHit(at: point) else { return }
        commitCellEdit()

        let nsText = textView.string as NSString
        let tableMarkdown = nsText.substring(with: hit.tableRange)
        let current = TableEditor.cell(in: tableMarkdown, rowIndex: hit.rowIndex, columnIndex: hit.columnIndex) ?? ""

        // A neat editing band inside the cell. The rendered cell text is suppressed
        // (see updateDrawingInfo), so a clean opaque field with an accent outline
        // is all that shows — no doubled text, no reflow.
        let cell = hit.cellRect
        let fieldHeight = min(cell.height - 6, 26)
        let fieldFrame = NSRect(
            x: cell.minX + 10,
            y: cell.midY - fieldHeight / 2,
            width: max(20, cell.width - 18),
            height: fieldHeight
        )
        let field = NSTextField(frame: fieldFrame)
        field.stringValue = current
        field.font = hit.rowIndex < 0 ? theme.tableHeaderFont() : theme.tableFont()
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = theme.backgroundColor
        field.textColor = theme.textColor
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.wantsLayer = true
        field.layer?.cornerRadius = 4
        field.layer?.borderWidth = 1.5
        field.layer?.borderColor = theme.accentColor.cgColor
        field.target = self
        field.action = #selector(cellEditorCommitted)
        field.delegate = self

        textView.addSubview(field)
        cellEditor = field
        cellEditContext = hit.ref
        activeCell = hit.ref
        window?.makeFirstResponder(field)
        // Suppress the rendered text for the cell being edited (no double draw).
        updateDrawingInfo()
    }

    @objc func cellEditorCommitted() {
        commitCellEdit()
    }

    /// Mark a cell as active (showing its control button) without opening the
    /// inline editor. Returns false if the point isn't inside a table cell.
    @discardableResult
    func activateCell(at point: NSPoint) -> Bool {
        guard let hit = tableCellHit(at: point) else { return false }
        commitCellEdit()
        activeCell = hit.ref
        updateDrawingInfo()
        return true
    }

    func commitCellEdit() {
        guard let field = cellEditor, let ctx = cellEditContext else { return }
        let newValue = field.stringValue
        field.removeFromSuperview()
        cellEditor = nil
        cellEditContext = nil

        let nsText = textView.string as NSString
        guard NSMaxRange(ctx.tableRange) <= nsText.length else {
            activeCell = nil
            updateDrawingInfo()
            return
        }
        let tableMarkdown = nsText.substring(with: ctx.tableRange)
        let updated = TableEditor.setCell(
            in: tableMarkdown,
            rowIndex: ctx.rowIndex,
            columnIndex: ctx.columnIndex,
            value: newValue
        )
        if updated != tableMarkdown {
            applyRemoteEdit(TextEdit(range: ctx.tableRange, replacementText: updated))
            // The table may have changed length; keep the control on this cell.
            activeCell = TableCellRef(
                tableRange: NSRange(location: ctx.tableRange.location, length: (updated as NSString).length),
                rowIndex: ctx.rowIndex,
                columnIndex: ctx.columnIndex
            )
        }
        // restyleAll runs async after the edit; refresh the control now too.
        updateDrawingInfo()
    }

    /// Dismiss any active cell editor / control (e.g. when clicking outside a table).
    func endTableEditing() {
        let wasActive = cellEditor != nil || activeCell != nil
        commitCellEdit()
        activeCell = nil
        if wasActive { updateDrawingInfo() }
    }

    // MARK: - Verification Seams

    //
    // The table cell geometry (hit rects, the in-cell control button) is computed
    // from NSLayoutManager line fragments, which only exist after a layout pass.
    // Synthetic mouse events aren't available in unit tests, so these internal
    // helpers let tests force layout and drive the exact code paths a click takes.

    /// Force a layout pass at a fixed size so table geometry is computed without
    /// a hosting window, then refresh the drawing info.
    func layoutForTesting(width: CGFloat = 600, height: CGFloat = 2000) {
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        updateDrawingInfo()
    }

    /// Tables currently laid out for drawing.
    var tableInfosForTesting: [DrawingInfo.TableInfo] {
        textView.drawingInfo.tableInfos
    }

    /// The in-cell control button currently shown (caret-in-cell), if any.
    var tableControlForTesting: DrawingInfo.TableControl? {
        textView.drawingInfo.tableControl
    }

    /// Whether an inline cell editor field is currently open.
    var hasActiveCellEditor: Bool {
        cellEditor != nil
    }

    /// Read or replace the active cell editor's text (simulating user typing).
    var activeCellEditorValue: String? {
        get { cellEditor?.stringValue }
        set { cellEditor?.stringValue = newValue ?? "" }
    }

    // MARK: - Table Menu

    func showTableMenu(from view: NSView, at point: NSPoint) {
        makeTableMenu().popUp(positioning: nil, at: point, in: view)
    }

    /// The structural table-editing menu (add/delete row & column) shown by the
    /// in-cell control button and the contextual menu when the caret is in a table.
    func makeTableMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(tableMenuItem("Insert Row Above", #selector(menuInsertRowAbove)))
        menu.addItem(tableMenuItem("Insert Row Below", #selector(menuInsertRowBelow)))
        menu.addItem(.separator())
        menu.addItem(tableMenuItem("Insert Column Left", #selector(menuInsertColumnLeft)))
        menu.addItem(tableMenuItem("Insert Column Right", #selector(menuInsertColumnRight)))
        menu.addItem(.separator())
        menu.addItem(tableMenuItem("Delete Row", #selector(menuDeleteRow)))
        menu.addItem(tableMenuItem("Delete Column", #selector(menuDeleteColumn)))
        return menu
    }

    @objc func menuInsertTable() {
        insertTable(rows: 2, columns: 3)
    }

    func tableMenuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func menuInsertRowAbove() {
        insertTableRowAbove()
    }

    @objc func menuInsertRowBelow() {
        insertTableRowBelow()
    }

    @objc func menuInsertColumnLeft() {
        insertTableColumnLeft()
    }

    @objc func menuInsertColumnRight() {
        insertTableColumnRight()
    }

    @objc func menuDeleteRow() {
        deleteTableRow()
    }

    @objc func menuDeleteColumn() {
        deleteTableColumn()
    }

    func tableColumnWidths(for tableToken: MarkdownToken) -> [CGFloat] {
        let nsText = textView.string as NSString
        let font = theme.tableFont()
        var rows: [[String]] = []
        for token in cachedTokens where NSIntersectionRange(token.range, tableToken.range).length > 0 {
            switch token.type {
            case .tableHeaderRow, .tableDataRow:
                rows.append(TableCellParser.parseCells(from: nsText.substring(with: token.range)))
            default:
                break
            }
        }
        return TableCellParser.measureColumnWidths(rows: rows, font: font, padding: 28)
    }

    func tableDrawingInfo(
        for token: MarkdownToken,
        layoutManager: NSLayoutManager,
        containerOrigin: NSPoint
    ) -> DrawingInfo.TableInfo? {
        // Exact bounding rect (no extra padding) so rows divide evenly.
        let glyphRange = layoutManager.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil)
        var unionRect = NSRect.zero
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            unionRect = unionRect == .zero ? lineRect : unionRect.union(lineRect)
        }
        guard unionRect != .zero else { return nil }
        let bgRect = NSRect(
            x: containerOrigin.x,
            y: unionRect.origin.y + containerOrigin.y,
            width: textView.bounds.width - containerOrigin.x * 2,
            height: unionRect.height
        )

        let nsText = textView.string as NSString
        let font = PulpFont.systemFont(ofSize: theme.bodySize * 0.9)
        let headerFont = PulpFont.systemFont(ofSize: theme.bodySize * 0.9, weight: .semibold)

        var rowDataList: [DrawingInfo.TableRowData] = []

        for otherToken in cachedTokens {
            guard NSIntersectionRange(otherToken.range, token.range).length > 0 else { continue }

            switch otherToken.type {
            case .tableHeaderRow:
                let content = nsText.substring(with: otherToken.range)
                rowDataList.append(.init(cells: TableCellParser.parseCells(from: content), isHeader: true))
            case .tableDataRow:
                let content = nsText.substring(with: otherToken.range)
                rowDataList.append(.init(cells: TableCellParser.parseCells(from: content), isHeader: false))
            default:
                break
            }
        }

        let allCellRows = rowDataList.map(\.cells)
        let columnWidths = TableCellParser.measureColumnWidths(rows: allCellRows, font: font, padding: 28)

        // Uniform row height matches the minimumLineHeight set in MarkdownStyler.
        // Distribute the table's measured height evenly so header == data rows exactly.
        let rowCount = max(1, rowDataList.count)
        let rowHeight = bgRect.height / CGFloat(rowCount)

        return .init(
            backgroundRect: bgRect,
            rowHeight: rowHeight,
            columnWidths: columnWidths,
            rows: rowDataList,
            borderColor: theme.borderColor,
            strongBorderColor: theme.strongBorderColor,
            headerBackground: theme.tableHeaderBackground,
            rowStripeBackground: theme.tableRowStripeBackground,
            font: font,
            headerFont: headerFont,
            textColor: theme.textColor
        )
    }
}

#endif
