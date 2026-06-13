#if canImport(AppKit)
import AppKit
@testable import Pulp
import Testing

/// End-to-end checks that ⌫ / fn⌫ route through the marker-atom resolver on a
/// real `PulpNSTextView`: the deletion lands as one grouped, undoable edit and
/// never strands broken syntax. Runs headless via the `deleteForTesting` seam —
/// synthetic key events don't drive this view.
@Suite("Atomic deletion (macOS wiring)")
@MainActor
struct AtomicDeletionTests {
    private func makeEditor(_ text: String, caret: Int) -> PulpNSTextView {
        let view = PulpNSTextView()
        view.setText(text)
        view.layoutForTesting(height: 2000)
        view.selectedRange = NSRange(location: caret, length: 0)
        return view
    }

    @Test("Backspace at task content start deletes the whole prefix in one press")
    func backspaceDeletesTaskPrefix() {
        let view = makeEditor("- [ ] asdsad", caret: 6)
        let handled = view.deleteForTesting(.backward)
        #expect(handled)
        #expect(view.text == "asdsad")
        #expect(view.selectedRange == NSRange(location: 0, length: 0))
    }

    @Test("The six-press case: deleting content is characterwise, the 7th press removes the prefix")
    func sixPressesThenPrefix() {
        // Caret after "asdsad" (6 content chars). Six backspaces delete the
        // content characterwise; the seventh, now at content start, dissolves
        // the checkbox — content chars + 1 press total.
        let view = makeEditor("- [ ] asdsad", caret: 12)
        for _ in 0 ..< 6 {
            #expect(view.deleteForTesting(.backward) == false) // characterwise
        }
        #expect(view.text == "- [ ] ")
        #expect(view.deleteForTesting(.backward)) // atomic prefix removal
        #expect(view.text.isEmpty)
    }

    @Test("One ⌘Z restores the deleted checkbox")
    func undoRestoresCheckboxInOneStep() {
        let view = makeEditor("- [ ] task", caret: 6)
        #expect(view.deleteForTesting(.backward))
        #expect(view.text == "task")
        view.editorUndoManager.undo()
        #expect(view.text == "- [ ] task")
    }

    @Test("Bold unwraps to its content on one backspace")
    func backspaceUnwrapsBold() {
        let view = makeEditor("**bold**", caret: 8)
        #expect(view.deleteForTesting(.backward))
        #expect(view.text == "bold")
        #expect(view.selectedRange == NSRange(location: 4, length: 0))
    }

    @Test("Forward-delete at line start removes the prefix")
    func forwardDeleteRemovesPrefix() {
        let view = makeEditor("# Heading", caret: 0)
        #expect(view.deleteForTesting(.forward))
        #expect(view.text == "Heading")
    }

    @Test("No broken-syntax invariant: backspacing a styled line to empty never strands markers")
    func backspacingStyledLineNeverStrandsMarkers() {
        // Walk the caret back through "**bold**" one press at a time. After every
        // press, re-tokenizing must not surface an orphaned bold token (which a
        // bare close-marker delete would have created).
        let view = makeEditor("**bold**", caret: 8)
        let tokenizer = MarkdownTokenizer()
        var guardCount = 0
        while !view.text.isEmpty, guardCount < 20 {
            view.deleteForTesting(.backward)
            let line = view.text
            let tokens = tokenizer.tokenize(line)
            // An orphan marker would re-tokenize as emphasis spanning leftover `*`s.
            #expect(!tokens.contains { $0.type == .bold || $0.type == .italic })
            guardCount += 1
        }
        #expect(view.text.isEmpty)
    }

    @Test("Selection delete is left to the platform (characterwise)")
    func selectionDeleteIsCharacterwise() {
        let view = makeEditor("**bold**", caret: 0)
        view.selectedRange = NSRange(location: 2, length: 4) // select "bold"
        #expect(view.deleteForTesting(.backward) == false)
        #expect(view.text == "****")
    }

    @Test("Plain text backspace stays characterwise")
    func plainTextCharacterwise() {
        let view = makeEditor("hello", caret: 5)
        #expect(view.deleteForTesting(.backward) == false)
        #expect(view.text == "hell")
    }
}
#endif
