#if canImport(AppKit)
import AppKit
import Foundation

public final class PulpNSTextView: NSView, PulpEditorProtocol {
    public weak var delegate: PulpEditorDelegate?

    public var theme: PulpTheme {
        didSet {
            styler.theme = theme
            restyleAll()
        }
    }

    public var isEditable: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    public var text: String {
        textView.string
    }

    public var selectedRange: NSRange {
        get { textView.selectedRange() }
        set { textView.setSelectedRange(newValue) }
    }

    public var derivedTitle: String {
        _derivedTitle
    }

    public var derivedTags: [String] {
        _derivedTags
    }

    public var hasUncheckedTodos: Bool {
        _hasUncheckedTodos
    }

    private let textView: PulpInternalTextView
    private let scrollView: NSScrollView
    private let tokenizer = MarkdownTokenizer()
    private let styler: MarkdownStyler
    private var isApplyingStyle = false
    private var isApplyingRemoteEdit = false
    private var cachedTokens: [MarkdownToken] = []
    private var previousSelectionLineRange: NSRange?

    private var _derivedTitle = ""
    private var _derivedTags: [String] = []
    private var _hasUncheckedTodos = false

    // Inline table cell editing
    private var cellEditor: NSTextField?
    private var cellEditContext: (tableRange: NSRange, rowIndex: Int, columnIndex: Int)?
    /// The cell whose control button is shown (last clicked / being edited). Drives
    /// the control independently of the text caret so clicks never move the caret.
    private var activeCell: (tableRange: NSRange, rowIndex: Int, columnIndex: Int)?

    public init(theme: PulpTheme = .default) {
        self.theme = theme
        self.styler = MarkdownStyler(theme: theme)

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        textView = PulpInternalTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false

        super.init(frame: .zero)

        textView.textStorage?.delegate = self
        textView.delegate = self
        textView.pulpParent = self

        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        configureTextContainer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(theme:)")
    }

    override public func layout() {
        super.layout()
        updateDrawingInfo()
    }

    private func configureTextContainer() {
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 40, height: 20)
    }

    // MARK: - Public API

    public func setText(_ text: String) {
        isApplyingStyle = true
        textView.string = text
        isApplyingStyle = false
        restyleAll()
        updateDerivedProperties()
    }

    public func applyRemoteEdit(_ edit: TextEdit) {
        isApplyingRemoteEdit = true
        let currentSelection = selectedRange

        guard let textStorage = textView.textStorage else {
            isApplyingRemoteEdit = false
            return
        }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: edit.range, with: edit.replacementText)
        textStorage.endEditing()

        let delta = edit.replacementText.count - edit.range.length
        var newSelection = currentSelection
        if edit.range.location <= currentSelection.location {
            newSelection.location = max(0, currentSelection.location + delta)
        }
        textView.setSelectedRange(newSelection)
        isApplyingRemoteEdit = false
    }

    // MARK: - Styling

    private func restyleAll() {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        cachedTokens = tokenizer.tokenize(textStorage.string)

        isApplyingStyle = true
        textStorage.beginEditing()
        textStorage.setAttributes(styler.baseAttributes(), range: fullRange)

        for run in styler.styleRuns(for: cachedTokens) {
            guard NSIntersectionRange(run.range, fullRange).length == run.range.length else { continue }
            textStorage.addAttributes(run.attributes, range: run.range)
        }

        revealMarkersInSelectionLine()
        textStorage.endEditing()
        isApplyingStyle = false

        updateDrawingInfo()
    }

    private func restyleParagraph(at location: Int) {
        guard let textStorage = textView.textStorage else { return }
        guard textStorage.length > 0 else { return }
        let string = textStorage.string as NSString
        let safeLocation = min(location, string.length - 1)
        let paraRange = string.paragraphRange(for: NSRange(location: safeLocation, length: 0))

        cachedTokens = tokenizer.tokenize(textStorage.string)

        isApplyingStyle = true
        textStorage.beginEditing()
        textStorage.setAttributes(styler.baseAttributes(), range: paraRange)

        let fullRange = NSRange(location: 0, length: textStorage.length)
        for run in styler.styleRuns(for: cachedTokens) {
            guard NSIntersectionRange(run.range, fullRange).length == run.range.length else { continue }
            if NSIntersectionRange(run.range, paraRange).length > 0 ||
                run.range.location >= paraRange.location && run.range.location < paraRange.location + paraRange.length
            {
                textStorage.addAttributes(run.attributes, range: run.range)
            }
        }

        revealMarkersInSelectionLine()
        textStorage.endEditing()
        isApplyingStyle = false

        updateDrawingInfo()
    }

    // MARK: - Selection-Aware Marker Reveal

    private func revealMarkersInSelectionLine() {
        guard let textStorage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        guard sel.location <= textStorage.length else { return }

        let string = textStorage.string as NSString
        let cursorLine = string.paragraphRange(for: NSRange(location: min(sel.location, string.length), length: 0))

        for token in cachedTokens {
            if NSIntersectionRange(token.range, cursorLine).length > 0 {
                for markerRange in token.markerRanges {
                    let clipped = NSIntersectionRange(markerRange, NSRange(location: 0, length: textStorage.length))
                    guard clipped.length > 0 else { continue }

                    switch token.type {
                    case .heading:
                        textStorage.addAttributes([
                            .font: theme.headingFont(level: headingLevel(token)),
                            .foregroundColor: theme.secondaryTextColor,
                        ], range: clipped)
                    case .listItem, .taskItem, .orderedListItem, .horizontalRule,
                         .table, .tableHeaderRow, .tableDataRow, .tableSeparatorRow:
                        // Table markers stay hidden at all times — revealing the raw
                        // pipes/separator on caret entry reflows the row and misaligns
                        // the rendered overlay. Editing happens through the cell editor.
                        break
                    case .codeBlock:
                        textStorage.addAttributes([
                            .font: PulpFont.monospacedSystemFont(ofSize: theme.bodySize * 0.8, weight: .regular),
                            .foregroundColor: theme.secondaryTextColor,
                        ], range: clipped)
                    default:
                        textStorage.addAttributes([
                            .font: PulpFont.systemFont(ofSize: theme.bodySize * 0.85),
                            .foregroundColor: theme.secondaryTextColor,
                        ], range: clipped)
                    }
                }
            }
        }
    }

    private func headingLevel(_ token: MarkdownToken) -> Int {
        if case let .heading(level) = token.type { return level }
        return 1
    }

    func handleSelectionChange() {
        // Don't restyle/reflow while an inline cell editor is open — that would
        // shift the overlay out from under the field.
        guard cellEditor == nil else { return }
        guard let textStorage = textView.textStorage else { return }
        let string = textStorage.string as NSString
        guard string.length > 0 else { return }

        let sel = textView.selectedRange()
        let currentLine = string.paragraphRange(for: NSRange(location: min(sel.location, string.length), length: 0))

        if let prev = previousSelectionLineRange, prev != currentLine {
            restyleAll()
        } else {
            isApplyingStyle = true
            textStorage.beginEditing()
            revealMarkersInSelectionLine()
            textStorage.endEditing()
            isApplyingStyle = false
        }

        previousSelectionLineRange = currentLine
    }

    // MARK: - Drawing Info

    private func updateDrawingInfo() {
        guard let layoutManager = textView.layoutManager,
              textView.textContainer != nil else { return }

        var info = DrawingInfo()
        info.theme = theme
        let containerOrigin = textView.textContainerOrigin

        for token in cachedTokens {
            switch token.type {
            case .codeBlock:
                if let rect = codeBlockRect(for: token, layoutManager: layoutManager, containerOrigin: containerOrigin) {
                    info.codeBlockRects.append(rect)
                }
            case .horizontalRule:
                if let rect = lineRect(for: token, layoutManager: layoutManager, containerOrigin: containerOrigin) {
                    info.horizontalRuleRects.append(NSRect(x: 0, y: rect.origin.y, width: textView.bounds.width, height: rect.height))
                }
            case .listItem:
                if let rect = lineRect(for: token, layoutManager: layoutManager, containerOrigin: containerOrigin) {
                    let dotSize: CGFloat = 6
                    info.bulletRects.append(NSRect(
                        x: containerOrigin.x + 14,
                        y: rect.origin.y + (rect.height - dotSize) / 2,
                        width: dotSize, height: dotSize
                    ))
                }
            case let .taskItem(checked):
                if let rect = lineRect(for: token, layoutManager: layoutManager, containerOrigin: containerOrigin) {
                    let size: CGFloat = 16
                    info.checkboxItems.append(.init(
                        rect: NSRect(
                            x: containerOrigin.x + 7,
                            y: rect.origin.y + (rect.height - size) / 2,
                            width: size, height: size
                        ),
                        checked: checked
                    ))
                }
            case .table:
                if var tableInfo = tableDrawingInfo(for: token, layoutManager: layoutManager, containerOrigin: containerOrigin) {
                    // Suppress the rendered text of the cell currently being edited.
                    if let ctx = cellEditContext, ctx.tableRange == token.range {
                        tableInfo.editingCell = (displayRow: ctx.rowIndex < 0 ? 0 : ctx.rowIndex + 1, column: ctx.columnIndex)
                    }
                    info.tableInfos.append(tableInfo)
                }
            default:
                break
            }
        }

        info.tableControl = tableControlInfo()

        textView.drawingInfo = info
        textView.needsDisplay = true
    }

    /// The control button is shown for the active cell — the one last clicked (so
    /// it survives after a cell edit commits) or, failing that, the cell the caret
    /// sits in (keyboard navigation). Hidden while the inline editor field is open
    /// (the field covers that cell).
    private func tableControlInfo() -> DrawingInfo.TableControl? {
        guard isEditable, cellEditor == nil else { return nil }

        if let cell = activeCell {
            return controlButton(tableRange: cell.tableRange, sourceRow: cell.rowIndex, columnIndex: cell.columnIndex)
        }
        guard let ctx = tableCaretContext() else { return nil }
        let sourceRow = ctx.isInHeader ? -1 : ctx.dataRowIndex
        return controlButton(tableRange: ctx.tableRange, sourceRow: sourceRow, columnIndex: ctx.columnIndex)
    }

    /// Compute the control button rect for a specific cell (sourceRow -1 = header).
    private func controlButton(tableRange: NSRange, sourceRow: Int, columnIndex: Int) -> DrawingInfo.TableControl? {
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

    /// Hit-test a point against tables. Returns the source cell coordinates and the
    /// on-screen cell rect, or nil if the point isn't inside a table cell.
    func tableCellHit(at point: NSPoint) -> (tableRange: NSRange, rowIndex: Int, columnIndex: Int, cellRect: NSRect)? {
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
            return (tableRange, sourceRow, colIdx, cellRect)
        }
        return nil
    }

    private func displayRowToDataRow(table: DrawingInfo.TableInfo, displayIndex: Int) -> Int {
        var dataIdx = -1
        for i in 0 ... displayIndex where !table.rows[i].isHeader {
            dataIdx += 1
        }
        return dataIdx
    }

    private func tableRange(matching bgRect: NSRect) -> NSRange? {
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
        cellEditContext = (hit.tableRange, hit.rowIndex, hit.columnIndex)
        activeCell = (hit.tableRange, hit.rowIndex, hit.columnIndex)
        window?.makeFirstResponder(field)
        // Suppress the rendered text for the cell being edited (no double draw).
        updateDrawingInfo()
    }

    @objc private func cellEditorCommitted() {
        commitCellEdit()
    }

    /// Mark a cell as active (showing its control button) without opening the
    /// inline editor. Returns false if the point isn't inside a table cell.
    @discardableResult
    func activateCell(at point: NSPoint) -> Bool {
        guard let hit = tableCellHit(at: point) else { return false }
        commitCellEdit()
        activeCell = (hit.tableRange, hit.rowIndex, hit.columnIndex)
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
            activeCell = (
                NSRange(location: ctx.tableRange.location, length: (updated as NSString).length),
                ctx.rowIndex,
                ctx.columnIndex
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

    private func tableMenuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuInsertRowAbove() {
        insertTableRowAbove()
    }

    @objc private func menuInsertRowBelow() {
        insertTableRowBelow()
    }

    @objc private func menuInsertColumnLeft() {
        insertTableColumnLeft()
    }

    @objc private func menuInsertColumnRight() {
        insertTableColumnRight()
    }

    @objc private func menuDeleteRow() {
        deleteTableRow()
    }

    @objc private func menuDeleteColumn() {
        deleteTableColumn()
    }

    private func tableColumnWidths(for tableToken: MarkdownToken) -> [CGFloat] {
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

    private func tableDrawingInfo(
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

    private func codeBlockRect(
        for token: MarkdownToken,
        layoutManager: NSLayoutManager,
        containerOrigin: NSPoint
    ) -> NSRect? {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil)
        var unionRect = NSRect.zero

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            unionRect = unionRect == .zero ? lineRect : unionRect.union(lineRect)
        }

        guard unionRect != .zero else { return nil }
        let padding: CGFloat = 8
        return NSRect(
            x: containerOrigin.x,
            y: unionRect.origin.y + containerOrigin.y - padding,
            width: textView.bounds.width - containerOrigin.x * 2,
            height: unionRect.height + padding * 2
        )
    }

    private func lineRect(
        for token: MarkdownToken,
        layoutManager: NSLayoutManager,
        containerOrigin: NSPoint
    ) -> NSRect? {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: token.range.location, length: 1),
            actualCharacterRange: nil
        )
        let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        return NSRect(
            x: rect.origin.x + containerOrigin.x,
            y: rect.origin.y + containerOrigin.y,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - Derived Properties

    private func updateDerivedProperties() {
        let content = text
        let oldTitle = _derivedTitle
        let oldTags = _derivedTags
        let oldTodos = _hasUncheckedTodos

        _derivedTitle = ContentAnalyzer.extractTitle(from: content)
        _derivedTags = ContentAnalyzer.extractTags(from: content)
        _hasUncheckedTodos = ContentAnalyzer.hasUncheckedTodos(in: content)

        if _derivedTitle != oldTitle {
            delegate?.editor(self, didUpdateTitle: _derivedTitle)
        }
        if _derivedTags != oldTags {
            delegate?.editor(self, didUpdateTags: _derivedTags)
        }
        if _hasUncheckedTodos != oldTodos {
            delegate?.editor(self, didUpdateHasUncheckedTodos: _hasUncheckedTodos)
        }
    }

    // MARK: - Checkbox Toggle

    public func toggleCheckbox(at characterIndex: Int) {
        let string = textView.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: characterIndex, length: 0))
        let line = string.substring(with: lineRange)

        if let regex = try? NSRegularExpression(pattern: "- \\[ \\]"),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        {
            let replaceRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            textView.insertText("- [x]", replacementRange: replaceRange)
            let lineNum = string.substring(to: lineRange.location).components(separatedBy: "\n").count - 1
            delegate?.editor(self, didToggleCheckboxAtLine: lineNum, checked: true)
        } else if let regex = try? NSRegularExpression(pattern: "- \\[[xX]\\]"),
                  let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        {
            let replaceRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            textView.insertText("- [ ]", replacementRange: replaceRange)
            let lineNum = string.substring(to: lineRange.location).components(separatedBy: "\n").count - 1
            delegate?.editor(self, didToggleCheckboxAtLine: lineNum, checked: false)
        }
    }
}

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

        for bulletRect in drawingInfo.bulletRects where bulletRect.intersects(dirtyRect) {
            theme.accentColor.setFill()
            NSBezierPath(ovalIn: bulletRect).fill()
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
        control.accentColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()

        // Three white dots (⋯) to signal a menu.
        NSColor.white.setFill()
        let dotSize: CGFloat = 2.2
        let gap: CGFloat = 3.5
        let centerY = rect.midY - dotSize / 2
        let startX = rect.midX - gap - dotSize / 2
        for i in 0 ..< 3 {
            let dot = NSRect(x: startX + CGFloat(i) * gap - dotSize / 2 + dotSize / 2, y: centerY, width: dotSize, height: dotSize)
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

        if let control = drawingInfo.tableControl, control.buttonRect.insetBy(dx: -4, dy: -4).contains(point) {
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

// MARK: - NSTextStorageDelegate

extension PulpNSTextView: NSTextStorageDelegate {
    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard !isApplyingStyle else { return }
        guard editedMask.contains(.editedCharacters) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if editedRange.length < 500, delta.magnitude < 200 {
                self.restyleParagraph(at: editedRange.location)
            } else {
                self.restyleAll()
            }
            self.updateDerivedProperties()
        }

        if !isApplyingRemoteEdit {
            let edit = TextEdit(
                range: NSRange(location: editedRange.location, length: max(0, editedRange.length - delta)),
                replacementText: (textStorage.string as NSString).substring(with: editedRange)
            )
            delegate?.editor(self, didApplyEdit: edit)
        }
    }
}

// MARK: - NSTextViewDelegate

extension PulpNSTextView: NSTextFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertTab(_:)) {
            commitCellEdit()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cellEditor?.removeFromSuperview()
            cellEditor = nil
            cellEditContext = nil
            return true
        }
        return false
    }
}

extension PulpNSTextView: NSTextViewDelegate {
    public func textViewDidChangeSelection(_ notification: Notification) {
        handleSelectionChange()
    }

    public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let urlString = link as? String, let url = URL(string: urlString) {
            delegate?.editor(self, didTapLink: url)
            return true
        }
        if let url = link as? URL {
            delegate?.editor(self, didTapLink: url)
            return true
        }
        return false
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return handleNewline(textView)
        }
        return false
    }

    private func handleNewline(_ textView: NSTextView) -> Bool {
        let string = textView.string as NSString
        let cursorPos = textView.selectedRange().location
        let lineRange = string.lineRange(for: NSRange(location: cursorPos, length: 0))
        let line = string.substring(with: lineRange)

        if let regex = try? NSRegularExpression(pattern: "^(\\s*)- \\[[ xX]\\] "),
           regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
        {
            let indent = extractIndent(from: line)
            let afterCheckbox = line.replacingOccurrences(of: "^\\s*- \\[[ xX]\\] ", with: "", options: .regularExpression)
            if afterCheckbox.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textView.insertText("\n", replacementRange: NSRange(location: lineRange.location, length: lineRange.length))
                return true
            }
            textView.insertText("\n\(indent)- [ ] ", replacementRange: textView.selectedRange())
            return true
        }

        if let regex = try? NSRegularExpression(pattern: "^(\\s*)([-*+]) "),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        {
            let indent = (line as NSString).substring(with: match.range(at: 1))
            let bullet = (line as NSString).substring(with: match.range(at: 2))
            let afterBullet = line.replacingOccurrences(of: "^\\s*[-*+] ", with: "", options: .regularExpression)
            if afterBullet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textView.insertText("\n", replacementRange: NSRange(location: lineRange.location, length: lineRange.length))
                return true
            }
            textView.insertText("\n\(indent)\(bullet) ", replacementRange: textView.selectedRange())
            return true
        }

        return false
    }

    private func extractIndent(from line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "^(\\s*)"),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else {
            return ""
        }
        return (line as NSString).substring(with: match.range(at: 1))
    }
}
#endif
