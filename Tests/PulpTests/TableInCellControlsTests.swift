#if canImport(AppKit)
import AppKit
import Foundation
@testable import Pulp
import Testing

/// Verifies the layout-dependent table controls — the in-cell control button and
/// click-to-edit — by forcing a layout pass and driving the exact code paths a
/// mouse click takes (synthetic mouse events aren't available in unit tests).
@MainActor
@Suite("TableInCellControls")
struct TableInCellControlsTests {
    private let table = "| Name | Status |\n| --- | --- |\n| Alpha | Done |\n| Beta | Todo |"

    private func laidOutEditor() -> PulpNSTextView {
        let view = PulpNSTextView()
        // Table is not at the very top, so caret-outside cases are meaningful.
        view.setText("# Title\n\n" + table)
        view.layoutForTesting()
        return view
    }

    /// Centre point (in view coords) of a display row / source column of the table.
    private func cellPoint(_ info: DrawingInfo.TableInfo, displayRow: Int, column: Int) -> NSPoint {
        let total = info.columnWidths.reduce(0, +)
        let scale = info.backgroundRect.width / total
        var x = info.backgroundRect.minX
        for i in 0 ..< column {
            x += info.columnWidths[i] * scale
        }
        x += info.columnWidths[column] * scale / 2
        let y = info.backgroundRect.minY + (CGFloat(displayRow) + 0.5) * info.rowHeight
        return NSPoint(x: x, y: y)
    }

    @Test func tableIsLaidOut() {
        let view = laidOutEditor()
        #expect(view.tableInfosForTesting.count == 1)
        #expect(view.tableInfosForTesting.first?.rows.count == 3) // header + 2 data rows
    }

    @Test func controlButtonAppearsWhenCaretInCell() {
        let view = laidOutEditor()
        let loc = (view.text as NSString).range(of: "Beta").location + 1
        view.selectedRange = NSRange(location: loc, length: 0)
        view.layoutForTesting()

        let control = view.tableControlForTesting
        #expect(control != nil)
        if let control, let info = view.tableInfosForTesting.first {
            // The button sits within the table's bounds.
            #expect(info.backgroundRect.intersects(control.buttonRect))
        }
    }

    @Test func noControlButtonWhenCaretOutsideTable() {
        let view = laidOutEditor()
        view.selectedRange = NSRange(location: 2, length: 0) // inside "# Title"
        view.layoutForTesting()
        #expect(view.tableControlForTesting == nil)
    }

    @Test func hitTestResolvesCorrectCell() {
        let view = laidOutEditor()
        guard let info = view.tableInfosForTesting.first else {
            Issue.record("table not laid out")
            return
        }
        // Display row 1 = first data row; column 0.
        let hit = view.tableCellHit(at: cellPoint(info, displayRow: 1, column: 0))
        #expect(hit?.rowIndex == 0)
        #expect(hit?.columnIndex == 0)

        // Display row 2 = second data row; column 1.
        let hit2 = view.tableCellHit(at: cellPoint(info, displayRow: 2, column: 1))
        #expect(hit2?.rowIndex == 1)
        #expect(hit2?.columnIndex == 1)
    }

    @Test func clickingCellOpensEditorPrefilledWithCellValue() {
        let view = laidOutEditor()
        guard let info = view.tableInfosForTesting.first else {
            Issue.record("table not laid out")
            return
        }
        let point = cellPoint(info, displayRow: 1, column: 0)
        view.beginEditingCell(at: point)

        #expect(view.hasActiveCellEditor)
        #expect(view.activeCellEditorValue == "Alpha")
    }

    @Test func editingCellWritesBackToSource() {
        let view = laidOutEditor()
        guard let info = view.tableInfosForTesting.first else {
            Issue.record("table not laid out")
            return
        }
        view.beginEditingCell(at: cellPoint(info, displayRow: 1, column: 0))
        view.activeCellEditorValue = "Renamed"
        view.commitCellEdit()

        #expect(!view.hasActiveCellEditor)
        #expect(view.text.contains("Renamed"))
        #expect(!view.text.contains("Alpha"))
    }

    @Test func contextMenuOffersInsertTableOutsideTable() {
        let view = laidOutEditor()
        let titles = view.makeTableMenu().items.map(\.title)
        #expect(titles.contains("Insert Row Above"))
        #expect(titles.contains("Insert Column Right"))
        #expect(titles.contains("Delete Row"))
        #expect(titles.contains("Delete Column"))
    }

    @Test func editingCellSuppressesItsRenderedText() {
        let view = laidOutEditor()
        guard let info = view.tableInfosForTesting.first else {
            Issue.record("table not laid out")
            return
        }
        view.beginEditingCell(at: cellPoint(info, displayRow: 1, column: 0))

        // The drawing info must mark this cell as edited so drawTable skips it
        // (no doubled text under the field).
        let edited = view.tableInfosForTesting.first?.editingCell
        #expect(edited?.displayRow == 1)
        #expect(edited?.column == 0)
    }

    @Test func controlPersistsAfterCommit() {
        let view = laidOutEditor()
        guard let info = view.tableInfosForTesting.first else {
            Issue.record("table not laid out")
            return
        }
        view.beginEditingCell(at: cellPoint(info, displayRow: 1, column: 0))
        view.activeCellEditorValue = "Renamed"
        view.commitCellEdit()
        view.layoutForTesting()

        // After committing, the field is gone but the control stays on the cell.
        #expect(!view.hasActiveCellEditor)
        #expect(view.tableControlForTesting != nil)
    }

    @Test func activatingCellShowsControlWithoutEditor() {
        let view = laidOutEditor()
        guard let info = view.tableInfosForTesting.first else {
            Issue.record("table not laid out")
            return
        }
        let activated = view.activateCell(at: cellPoint(info, displayRow: 2, column: 1))
        #expect(activated)
        #expect(!view.hasActiveCellEditor)
        #expect(view.tableControlForTesting != nil)
    }

    @Test func endTableEditingClearsControl() {
        let view = laidOutEditor()
        guard let info = view.tableInfosForTesting.first else {
            Issue.record("table not laid out")
            return
        }
        view.activateCell(at: cellPoint(info, displayRow: 1, column: 0))
        view.endTableEditing()
        view.layoutForTesting()
        #expect(view.tableControlForTesting == nil)
    }

    @Test func structuralCommandsUseActivatedCellNotCaret() throws {
        let view = laidOutEditor()
        // Caret is outside the table (start of document), so these commands must
        // rely on the activated cell, not the caret.
        view.selectedRange = NSRange(location: 0, length: 0)
        guard let info = view.tableInfosForTesting.first else {
            Issue.record("table not laid out")
            return
        }
        view.activateCell(at: cellPoint(info, displayRow: 1, column: 0)) // first data row
        view.insertTableRowBelow()

        // A blank row was inserted after the first data row (Alpha/Done).
        let table = MarkdownTokenizer().tokenize(view.text).first {
            if case .table = $0.type { return true }
            return false
        }
        let md = try (view.text as NSString).substring(with: #require(table?.range))
        let parsed = TableEditor.parse(md)
        #expect(parsed?.rows.count == 3)
        #expect(parsed?.rows[0] == ["Alpha", "Done"])
        #expect(parsed?.rows[1] == ["", ""])
    }

    /// Two *padded* (aligned) tables like the demo, separated by a paragraph.
    private let paddedTwoTables = """
    # Doc

    | Feature              | Status  | Priority |
    |----------------------|---------|----------|
    | Headings             | Done    | P0       |
    | Task Lists           | Done    | P0       |
    | Tables               | New     | P1       |

    A second table with longer content:

    | Name | Description              | Rating |
    |------|--------------------------|--------|
    | Pulp | Inline Markdown editor   | 5      |
    | Kiem | P2P notes with CRDT sync | 4      |
    """

    private func paddedEditor() -> PulpNSTextView {
        let view = PulpNSTextView()
        view.setText(paddedTwoTables)
        view.layoutForTesting(height: 3000)
        return view
    }

    @Test func clickingPaddedCellsDoesNotReformatOrCorrupt() {
        let view = paddedEditor()
        let original = view.text
        guard let first = view.tableInfosForTesting.first else {
            Issue.record("no table")
            return
        }
        // Open and close several cells in the first (padded) table without typing.
        for (row, col) in [(1, 1), (2, 0), (1, 2), (3, 1)] {
            view.beginEditingCell(at: cellPoint(first, displayRow: row, column: col))
            view.commitCellEdit()
        }
        // No value changed → source must be byte-identical (no canonical reformat,
        // no merge). This is the "just clicking around corrupts" repro.
        #expect(view.text == original)
        let tableCount = MarkdownTokenizer().tokenize(view.text).filter {
            if case .table = $0.type { return true }
            return false
        }.count
        #expect(tableCount == 2)
    }

    @Test func editingPaddedCellKeepsSecondTableIntact() {
        let view = paddedEditor()
        guard let first = view.tableInfosForTesting.first else {
            Issue.record("no table")
            return
        }
        view.beginEditingCell(at: cellPoint(first, displayRow: 1, column: 1)) // "Done"
        view.activeCellEditorValue = "Shipped"
        view.commitCellEdit()

        #expect(view.text.contains("Shipped"))
        #expect(view.text.contains("A second table with longer content:"))
        #expect(view.text.contains("Pulp"))
        let tableCount = MarkdownTokenizer().tokenize(view.text).filter {
            if case .table = $0.type { return true }
            return false
        }.count
        #expect(tableCount == 2)
    }

    @Test func clickingCellsRepeatedlyKeepsSourceValid() {
        let view = laidOutEditor()
        let original = view.text
        // Simulate clicking around several cells (table has 2 columns) without typing.
        for (row, col) in [(1, 0), (2, 1), (0, 1), (1, 1), (0, 0)] {
            guard let info = view.tableInfosForTesting.first else { break }
            view.beginEditingCell(at: cellPoint(info, displayRow: row, column: col))
            view.commitCellEdit()
        }
        // No typing means no change — and crucially no corruption/merge.
        #expect(view.text == original)
        #expect(view.text.contains("# Title"))

        let tables = MarkdownTokenizer().tokenize(view.text).filter {
            if case .table = $0.type { return true }
            return false
        }
        #expect(tables.count == 1)
    }
}
#endif
