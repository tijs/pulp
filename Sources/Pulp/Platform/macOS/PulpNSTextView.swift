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

    let textView: PulpInternalTextView
    private let scrollView: NSScrollView
    private let tokenizer = MarkdownTokenizer()
    private let styler: MarkdownStyler
    private var isApplyingStyle = false
    private var isApplyingRemoteEdit = false
    var cachedTokens: [MarkdownToken] = []
    private var previousSelectionLineRange: NSRange?

    private var _derivedTitle = ""
    private var _derivedTags: [String] = []
    private var _hasUncheckedTodos = false

    // Inline table cell editing
    var cellEditor: NSTextField?
    var cellEditContext: TableCellRef?
    /// The cell whose control button is shown (last clicked / being edited). Drives
    /// the control independently of the text caret so clicks never move the caret.
    var activeCell: TableCellRef?

    /// The active cell, with its table range re-resolved against current tokens so
    /// structural edits target the right table even after earlier edits shifted it.
    public var activeTableCell: TableCellRef? {
        guard let cell = activeCell else { return nil }
        if let token = cachedTokens.first(where: {
            guard case .table = $0.type else { return false }
            return NSLocationInRange(cell.tableRange.location, $0.range)
                || $0.range.location == cell.tableRange.location
        }) {
            return TableCellRef(tableRange: token.range, rowIndex: cell.rowIndex, columnIndex: cell.columnIndex)
        }
        return cell
    }

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

    /// Notify the delegate of a locally-originated edit (table cell / structural
    /// edits go through `applyRemoteEdit`, which suppresses the echo) so a consumer
    /// binding stays in sync. Also refreshes derived properties.
    func notifyLocalEdit(_ edit: TextEdit) {
        delegate?.editor(self, didApplyEdit: edit)
        updateDerivedProperties()
    }

    // MARK: - Styling

    func restyleAll() {
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
                run.range.location >= paraRange.location && run.range.location < paraRange.location + paraRange.length {
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

    /// Custom-drawn list-marker geometry. Glyphs sit `glyph width + gap` left of
    /// the text indent so the marker hangs in the margin just before its text.
    private static let bulletDotSize: CGFloat = 6
    private static let bulletTextGap: CGFloat = 8
    private static let checkboxSize: CGFloat = 16
    private static let checkboxTextGap: CGFloat = 5

    func updateDrawingInfo() {
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
                    // Sit the glyph in the margin just left of the text indent so
                    // nested bullets align under their text at every depth. The x
                    // is `textIndent - (glyph width + gap)`, derived from the same
                    // depth indent the styler uses for the text.
                    let textIndent = MarkdownStyler.listIndent(depth: token.indentDepth)
                    let x = containerOrigin.x + textIndent - (Self.bulletDotSize + Self.bulletTextGap)
                    info.bulletItems.append(.init(
                        rect: NSRect(
                            x: x,
                            y: rect.origin.y + (rect.height - Self.bulletDotSize) / 2,
                            width: Self.bulletDotSize, height: Self.bulletDotSize
                        ),
                        style: .forDepth(token.indentDepth)
                    ))
                }
            case let .taskItem(checked):
                if let rect = lineRect(for: token, layoutManager: layoutManager, containerOrigin: containerOrigin) {
                    let textIndent = MarkdownStyler.listIndent(depth: token.indentDepth)
                    let x = containerOrigin.x + textIndent - (Self.checkboxSize + Self.checkboxTextGap)
                    info.checkboxItems.append(.init(
                        rect: NSRect(
                            x: x,
                            y: rect.origin.y + (rect.height - Self.checkboxSize) / 2,
                            width: Self.checkboxSize, height: Self.checkboxSize
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
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            let replaceRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            textView.insertText("- [x]", replacementRange: replaceRange)
            let lineNum = string.substring(to: lineRange.location).components(separatedBy: "\n").count - 1
            delegate?.editor(self, didToggleCheckboxAtLine: lineNum, checked: true)
        } else if let regex = try? NSRegularExpression(pattern: "- \\[[xX]\\]"),
                  let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            let replaceRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            textView.insertText("- [ ]", replacementRange: replaceRange)
            let lineNum = string.substring(to: lineRange.location).components(separatedBy: "\n").count - 1
            delegate?.editor(self, didToggleCheckboxAtLine: lineNum, checked: false)
        }
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
           regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
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
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
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
