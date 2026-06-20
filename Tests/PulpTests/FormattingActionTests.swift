#if canImport(AppKit)
import AppKit
import Foundation
@testable import Pulp
import Testing

/// Integration tests for the host-facing formatting commands: the two new
/// protocol methods (`toggleOrderedList`, `insertLink`) and the typed
/// `PulpFormattingAction` facade that a host toolbar drives through
/// `PulpEditorController.perform(_:)`.
@MainActor
@Suite("FormattingActions")
struct FormattingActionTests {
    private func editor(_ text: String) -> PulpNSTextView {
        let view = PulpNSTextView()
        view.setText(text)
        return view
    }

    private func controller(for view: PulpNSTextView) -> PulpEditorController {
        let controller = PulpEditorController()
        controller.editor = view
        return controller
    }

    // MARK: - toggleOrderedList

    @Test func orderedListAddsPrefix() {
        let view = editor("Buy milk")
        view.selectedRange = NSRange(location: 0, length: 0)
        view.toggleOrderedList()
        #expect(view.text == "1. Buy milk")
    }

    @Test func orderedListTogglesOff() {
        let view = editor("1. Buy milk")
        view.selectedRange = NSRange(location: 5, length: 0)
        view.toggleOrderedList()
        #expect(view.text == "Buy milk")
    }

    // MARK: - insertLink

    @Test func insertLinkEmptySelectionPlacesCaretInBrackets() {
        let view = editor("")
        view.selectedRange = NSRange(location: 0, length: 0)
        view.insertLink()
        #expect(view.text == "[]()")
        // Caret sits between the brackets, ready for the link text.
        #expect(view.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test func insertLinkWrapsSelectionAndPlacesCaretInParens() {
        let view = editor("Anthropic")
        view.selectedRange = NSRange(location: 0, length: 9)
        view.insertLink()
        #expect(view.text == "[Anthropic]()")
        // Caret sits between the parens, ready for the URL: past "[Anthropic](".
        #expect(view.selectedRange == NSRange(location: 12, length: 0))
    }

    // MARK: - perform(_:) facade

    @Test func performBoldWrapsSelection() {
        let view = editor("word")
        let controller = controller(for: view)
        view.selectedRange = NSRange(location: 0, length: 4)
        controller.perform(.bold)
        #expect(view.text == "**word**")
    }

    @Test func performHeadingSetsLevel() {
        let view = editor("Title")
        let controller = controller(for: view)
        view.selectedRange = NSRange(location: 0, length: 0)
        controller.perform(.heading(2))
        #expect(view.text == "## Title")
    }

    @Test func performNumberListMapsToOrderedList() {
        let view = editor("First")
        let controller = controller(for: view)
        view.selectedRange = NSRange(location: 0, length: 0)
        controller.perform(.numberList)
        #expect(view.text == "1. First")
    }

    @Test func performLinkWrapsSelection() {
        let view = editor("here")
        let controller = controller(for: view)
        view.selectedRange = NSRange(location: 0, length: 4)
        controller.perform(.link)
        #expect(view.text == "[here]()")
    }

    @Test func performInsertTableProducesTable() {
        let view = editor("")
        let controller = controller(for: view)
        view.selectedRange = NSRange(location: 0, length: 0)
        controller.perform(.insertTable(rows: 2, columns: 3))
        let tables = MarkdownTokenizer().tokenize(view.text).filter {
            if case .table = $0.type { return true }
            return false
        }
        #expect(tables.count == 1)
    }
}
#endif
