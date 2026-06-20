#if canImport(AppKit)
import AppKit
import Foundation
@testable import Pulp
import Testing

/// Inline emphasis must wrap only a selection's *content*, never the block
/// marker (`- `, `1. `, `- [ ] `, `> `, `# `) and never across a table-cell pipe.
/// Regression coverage for the bug where bolding a selected list item produced
/// `*** asdasd**` and broke the bullet.
@MainActor
@Suite("EmphasisInBlocks")
struct EmphasisInBlocksTests {
    private func editor(_ text: String) -> PulpNSTextView {
        let view = PulpNSTextView()
        view.setText(text)
        return view
    }

    /// Select the whole line (marker included, as a user does when the marker is
    /// rendered invisibly) and bold it.
    private func boldWholeLine(_ text: String) -> String {
        let view = editor(text)
        view.selectedRange = NSRange(location: 0, length: (text as NSString).length)
        view.toggleBold()
        return view.text
    }

    // MARK: - The reported bug, across bullet flavors

    @Test func boldBulletItemKeepsMarker() {
        #expect(boldWholeLine("- asdasd") == "- **asdasd**")
        #expect(boldWholeLine("* asdasd") == "* **asdasd**")
        #expect(boldWholeLine("+ asdasd") == "+ **asdasd**")
    }

    @Test func boldIndentedBulletKeepsIndentAndMarker() {
        #expect(boldWholeLine("  - nested") == "  - **nested**")
    }

    // MARK: - Other block contexts

    @Test func boldOrderedItemKeepsNumber() {
        #expect(boldWholeLine("1. item") == "1. **item**")
    }

    @Test func boldTaskItemKeepsCheckbox() {
        #expect(boldWholeLine("- [ ] do it") == "- [ ] **do it**")
        #expect(boldWholeLine("- [x] done") == "- [x] **done**")
    }

    @Test func boldBlockquoteKeepsMarker() {
        #expect(boldWholeLine("> note") == "> **note**")
    }

    @Test func boldHeadingKeepsHashes() {
        #expect(boldWholeLine("## Title") == "## **Title**")
    }

    // MARK: - Every inline toggle behaves the same in a list item

    @Test func allTogglesRespectListMarker() {
        func apply(_ op: (PulpNSTextView) -> Void) -> String {
            let view = editor("- text")
            view.selectedRange = NSRange(location: 0, length: 6)
            op(view)
            return view.text
        }
        #expect(apply { $0.toggleItalic() } == "- *text*")
        #expect(apply { $0.toggleStrikethrough() } == "- ~~text~~")
        #expect(apply { $0.toggleHighlight() } == "- ==text==")
        #expect(apply { $0.toggleInlineCode() } == "- `text`")
    }

    // MARK: - Selecting just the content (caret not over the marker)

    @Test func boldContentOnlySelectionStillWraps() {
        let view = editor("- asdasd")
        // Select only "asdasd" (offset 2, length 6).
        view.selectedRange = NSRange(location: 2, length: 6)
        view.toggleBold()
        #expect(view.text == "- **asdasd**")
    }

    // MARK: - Tables: never cross a pipe

    @Test func boldSingleTableCell() {
        let table = "| a | b |\n| --- | --- |\n| c | d |"
        let view = editor(table)
        // Select "a" inside the header's first cell (offset 2, length 1).
        view.selectedRange = NSRange(location: 2, length: 1)
        view.toggleBold()
        #expect(view.text == "| **a** | b |\n| --- | --- |\n| c | d |")
    }

    @Test func boldAcrossTwoCellsWrapsEachNotThePipe() {
        let table = "| a | b |\n| --- | --- |\n| c | d |"
        let view = editor(table)
        // Select from "a" through "b": offset 2 .. 7 (covers "a | b").
        view.selectedRange = NSRange(location: 2, length: 5)
        view.toggleBold()
        #expect(view.text == "| **a** | **b** |\n| --- | --- |\n| c | d |")
    }

    // MARK: - Multi-line selection wraps each item independently

    @Test func boldTwoListItemsWrapsEach() {
        let view = editor("- one\n- two")
        view.selectedRange = NSRange(location: 0, length: (view.text as NSString).length)
        view.toggleBold()
        #expect(view.text == "- **one**\n- **two**")
    }

    // MARK: - Toggle off

    @Test func boldTwiceTogglesOffInsideList() {
        let view = editor("- asdasd")
        view.selectedRange = NSRange(location: 0, length: 8)
        view.toggleBold()
        #expect(view.text == "- **asdasd**")
        // Re-select the wrapped content and toggle off.
        view.selectedRange = NSRange(location: 2, length: (view.text as NSString).length - 2)
        view.toggleBold()
        #expect(view.text == "- asdasd")
    }

    // MARK: - Regressions for non-block text

    @Test func boldPlainParagraphUnchanged() {
        let view = editor("word")
        view.selectedRange = NSRange(location: 0, length: 4)
        view.toggleBold()
        #expect(view.text == "**word**")
    }

    @Test func boldExcludesTrailingNewline() {
        let view = editor("word\nnext")
        // Select "word\n" — the newline must stay outside the emphasis.
        view.selectedRange = NSRange(location: 0, length: 5)
        view.toggleBold()
        #expect(view.text == "**word**\nnext")
    }

    @Test func emptySelectionInsertsMarkersAndCentersCaret() {
        let view = editor("- ")
        view.selectedRange = NSRange(location: 2, length: 0)
        view.toggleBold()
        #expect(view.text == "- ****")
        #expect(view.selectedRange == NSRange(location: 4, length: 0))
    }
}
#endif
