#if canImport(AppKit)
import AppKit
import Foundation

/// Table rendering geometry, in-cell editing, and structural-edit menus for
/// the macOS editor. Split out of PulpNSTextView to keep that file focused.
extension PulpNSTextView {
    /// The control button is shown for the active cell — the one last clicked (so
    /// it survives after a cell edit commits and is visible *while* editing too),
    /// or, failing that, the cell the caret sits in (keyboard navigation). The
    /// inline editor field is inset on the right so the control stays clickable.
    func tableControlInfo() -> DrawingInfo.TableControl? {
        guard isEditable else { return nil }

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
        let containerOrigin = textView.textContainerOrigin
        guard let unionRect = segmentUnionRect(forCharacterRange: tableToken.range) else { return nil }

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

        let buttonSize: CGFloat = 24
        let buttonRect = NSRect(
            x: cellRight - buttonSize - 6,
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
        let containerOrigin = textView.textContainerOrigin
        for token in cachedTokens {
            guard case .table = token.type else { continue }
            guard let unionRect = segmentUnionRect(forCharacterRange: token.range) else { continue }
            let top = unionRect.origin.y + containerOrigin.y
            if abs(top - bgRect.minY) < 2 { return token.range }
        }
        return nil
    }

    /// Cell text inset used by both the overlay renderer and the inline editor so
    /// the editor's text sits exactly where the rendered text was (no jump).
    static let cellTextPadding: CGFloat = 14

    /// Edit a cell in place. Commit any prior edit first (which may reflow the
    /// document), then hit-test against the fresh layout so the captured range is
    /// always valid. The editor is a seamless, borderless field positioned exactly
    /// over the cell text — it looks like editing the rendered text directly.
    func beginEditingCell(at point: NSPoint) {
        commitCellEdit()
        guard let hit = tableCellHit(at: point) else { return }

        let nsText = textView.string as NSString
        let tableMarkdown = nsText.substring(with: hit.tableRange)
        let current = TableEditor.cell(in: tableMarkdown, rowIndex: hit.rowIndex, columnIndex: hit.columnIndex) ?? ""

        let pad = Self.cellTextPadding
        let cell = hit.cellRect
        // -3 compensates for NSTextField's internal text inset so the first glyph
        // lands at the same x the renderer used (cell.minX + pad). Reserve room on
        // the right (controlReserve) so the in-cell control button stays visible
        // and clickable while editing.
        let controlReserve: CGFloat = 34
        let field = SeamlessCellField(frame: NSRect(
            x: cell.minX + pad - 3,
            y: cell.minY,
            width: max(20, cell.width - pad - 3 - controlReserve),
            height: cell.height
        ))
        field.stringValue = current
        field.font = hit.rowIndex < 0 ? theme.tableHeaderFont() : theme.tableFont()
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = false
        field.textColor = theme.textColor
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
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
        let oldValue = TableEditor.cell(in: tableMarkdown, rowIndex: ctx.rowIndex, columnIndex: ctx.columnIndex) ?? ""

        // Only write back when the cell's value actually changed. Crucially this
        // makes merely clicking between cells a no-op — no rewrite, no reflow, so
        // captured ranges can never go stale and corrupt the document.
        guard newValue != oldValue else {
            updateDrawingInfo()
            return
        }

        let updated = TableEditor.setCell(
            in: tableMarkdown,
            rowIndex: ctx.rowIndex,
            columnIndex: ctx.columnIndex,
            value: newValue
        )
        guard updated != tableMarkdown else {
            updateDrawingInfo()
            return
        }
        applyRemoteEdit(TextEdit(range: ctx.tableRange, replacementText: updated))
        // Re-tokenize synchronously so any subsequent hit-test sees fresh ranges.
        restyleAll()
        notifyLocalEdit(TextEdit(range: ctx.tableRange, replacementText: updated))
        // The table may have changed length; keep the control on this cell.
        activeCell = TableCellRef(
            tableRange: NSRange(location: ctx.tableRange.location, length: (updated as NSString).length),
            rowIndex: ctx.rowIndex,
            columnIndex: ctx.columnIndex
        )
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
    // from laid-out text segment frames, which only exist after a layout pass.
    // Synthetic mouse events aren't available in unit tests, so these internal
    // helpers let tests force layout and drive the exact code paths a click takes.

    /// Force a layout pass at a fixed size so table geometry is computed without
    /// a hosting window, then refresh the drawing info (which itself lays out
    /// the full document first).
    func layoutForTesting(width: CGFloat = 600, height: CGFloat = 2000) {
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        updateDrawingInfo()
    }

    /// Tables currently laid out for drawing.
    var tableInfosForTesting: [DrawingInfo.TableInfo] {
        textView.drawingInfo.tableInfos
    }

    /// Custom-drawn list bullets currently laid out (for geometry tests).
    var bulletItemsForTesting: [DrawingInfo.BulletItem] {
        textView.drawingInfo.bulletItems
    }

    /// Custom-drawn task checkboxes currently laid out (for geometry tests).
    var checkboxItemsForTesting: [DrawingInfo.CheckboxItem] {
        textView.drawingInfo.checkboxItems
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

    func tableDrawingInfo(for token: MarkdownToken, containerOrigin: NSPoint) -> DrawingInfo.TableInfo? {
        // Exact bounding rect (no extra padding) so rows divide evenly.
        guard let unionRect = segmentUnionRect(forCharacterRange: token.range) else { return nil }
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

/// A borderless, transparent text field whose text is vertically centered, so the
/// inline cell editor sits exactly where the rendered cell text was — editing
/// looks in-place, with no visible box and no text jump.
final class SeamlessCellField: NSTextField {
    override class var cellClass: AnyClass? {
        get { VerticallyCenteredTextCell.self }
        set {}
    }
}

final class VerticallyCenteredTextCell: NSTextFieldCell {
    private func centered(_ rect: NSRect) -> NSRect {
        let height = cellSize(forBounds: rect).height
        guard height < rect.height else { return rect }
        var r = rect
        r.origin.y += (rect.height - height) / 2
        r.size.height = height
        return r
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centered(cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centered(rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: centered(rect), in: controlView, editor: editor, delegate: delegate, start: start, length: length)
    }
}

#endif
