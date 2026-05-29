#if canImport(AppKit)
import AppKit
import Foundation
@testable import Pulp
import Testing

/// Integration tests exercising the table editing commands against a real
/// `PulpNSTextView`. These cover the caret-resolution + source-mutation path
/// that drives the in-cell controls and inline editing — the parts that can't
/// be verified by eye in a screenshot.
@MainActor
@Suite("TableCommands")
struct TableCommandsTests {
    private func editor(_ text: String) -> PulpNSTextView {
        let view = PulpNSTextView()
        view.setText(text)
        return view
    }

    private let sample = "| Name | Status |\n| --- | --- |\n| Alpha | Done |\n| Beta | Todo |"

    /// Two tables separated by a paragraph, followed by a heading. Editing the
    /// first table must not consume the separating newlines or merge the tables.
    private let twoTables = """
    | A | B |
    | --- | --- |
    | 1 | 2 |

    Between the tables.

    | C | D |
    | --- | --- |
    | 3 | 4 |

    ## After
    """

    @Test func editingFirstTablePreservesDocumentStructure() {
        let view = editor(twoTables)
        // Edit a cell in the first table.
        let loc = (view.text as NSString).range(of: "1").location
        view.selectedRange = NSRange(location: loc, length: 0)
        view.insertTableRowBelow()

        // The paragraph, second table, and heading must all survive intact.
        #expect(view.text.contains("Between the tables."))
        #expect(view.text.contains("| C | D |"))
        #expect(view.text.contains("## After"))
        // Exactly two tables still tokenize.
        let tables = MarkdownTokenizer().tokenize(view.text).filter {
            if case .table = $0.type { return true }
            return false
        }
        #expect(tables.count == 2)
    }

    @Test func tableTokenRangeExcludesTrailingNewline() {
        let view = editor("| A | B |\n| --- | --- |\n| 1 | 2 |\n\nNext paragraph.")
        let tableToken = MarkdownTokenizer().tokenize(view.text).first {
            if case .table = $0.type { return true }
            return false
        }
        #expect(tableToken != nil)
        if let range = tableToken?.range {
            let last = (view.text as NSString).substring(with: range).last
            #expect(last == "|") // ends at the last cell pipe, not a newline
        }
    }

    @Test func insertTableIntoEmptyDocument() {
        let view = editor("")
        view.insertTable()
        let parsed = TableEditor.parse(view.text)
        #expect(parsed?.columnCount == 3)
        #expect(parsed?.rows.count == 2)
    }

    @Test func caretContextResolvesDataCell() {
        let view = editor(sample)
        // Place caret inside "Beta" (second data row, first column).
        let location = (view.text as NSString).range(of: "Beta").location + 1
        view.selectedRange = NSRange(location: location, length: 0)

        let ctx = view.tableCaretContext()
        #expect(ctx != nil)
        #expect(ctx?.isInHeader == false)
        #expect(ctx?.dataRowIndex == 1)
        #expect(ctx?.columnIndex == 0)
    }

    @Test func caretContextResolvesHeaderCell() {
        let view = editor(sample)
        let location = (view.text as NSString).range(of: "Status").location + 1
        view.selectedRange = NSRange(location: location, length: 0)

        let ctx = view.tableCaretContext()
        #expect(ctx?.isInHeader == true)
        #expect(ctx?.columnIndex == 1)
    }

    @Test func insertRowBelowCaret() {
        let view = editor(sample)
        let location = (view.text as NSString).range(of: "Alpha").location + 1
        view.selectedRange = NSRange(location: location, length: 0)

        view.insertTableRowBelow()
        let parsed = TableEditor.parse(view.text)
        #expect(parsed?.rows.count == 3)
        #expect(parsed?.rows[0] == ["Alpha", "Done"])
        #expect(parsed?.rows[1] == ["", ""])
        #expect(parsed?.rows[2] == ["Beta", "Todo"])
    }

    @Test func insertColumnRightOfCaret() {
        let view = editor(sample)
        let location = (view.text as NSString).range(of: "Name").location + 1
        view.selectedRange = NSRange(location: location, length: 0)

        view.insertTableColumnRight()
        let parsed = TableEditor.parse(view.text)
        #expect(parsed?.columnCount == 3)
        #expect(parsed?.header == ["Name", "Column", "Status"])
    }

    @Test func deleteRowAtCaret() {
        let view = editor(sample)
        let location = (view.text as NSString).range(of: "Alpha").location + 1
        view.selectedRange = NSRange(location: location, length: 0)

        view.deleteTableRow()
        let parsed = TableEditor.parse(view.text)
        #expect(parsed?.rows == [["Beta", "Todo"]])
    }

    @Test func noContextOutsideTable() {
        let view = editor("Just a paragraph, no table here.")
        view.selectedRange = NSRange(location: 3, length: 0)
        #expect(view.tableCaretContext() == nil)
    }
}
#endif
