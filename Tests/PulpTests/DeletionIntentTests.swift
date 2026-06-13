import Foundation
@testable import Pulp
import Testing

/// Unit tests for the platform-agnostic marker-atom deletion resolver. Each test
/// tokenizes real Markdown, places the caret at a boundary, and asserts the
/// resolved `DeletionAction` — covering every element family from the plan's
/// R1–R5 rule table, plus the escape hatches (mid-marker, selection, bounds).
@Suite("Deletion intent")
struct DeletionIntentTests {
    private let tokenizer = MarkdownTokenizer()

    /// Resolve a backspace/forward-delete with a plain caret at `caret`.
    private func resolve(
        _ text: String,
        caret: Int,
        direction: DeletionDirection = .backward
    ) -> DeletionAction {
        let tokens = tokenizer.tokenize(text)
        return DeletionIntent.resolve(
            text: text as NSString,
            tokens: tokens,
            caret: NSRange(location: caret, length: 0),
            direction: direction
        )
    }

    /// The single range of a `.ranges` action (fails the expectation otherwise).
    private func singleRange(_ action: DeletionAction) -> NSRange? {
        guard case let .ranges(ranges) = action, ranges.count == 1 else { return nil }
        return ranges[0]
    }

    /// Apply a `.ranges` action to `text` and return the result, so tests can
    /// assert the *outcome* the user sees, not just the ranges.
    private func applied(_ action: DeletionAction, to text: String) -> String {
        guard case let .ranges(ranges) = action else { return text }
        let mutable = NSMutableString(string: text)
        for range in ranges { // already descending — safe to apply in order
            mutable.replaceCharacters(in: range, with: "")
        }
        return mutable as String
    }

    // MARK: - R1: Block prefixes

    @Test("Screenshot case: backspace at task content start removes the whole prefix")
    func taskPrefixDeletedAtContentStart() {
        let text = "- [ ] asdsad"
        let action = resolve(text, caret: 6) // caret right after "- [ ] "
        #expect(singleRange(action) == NSRange(location: 0, length: 6))
        #expect(applied(action, to: text) == "asdsad")
    }

    @Test("Empty task line: prefix removed, line empties")
    func emptyTaskLinePrefixRemoved() {
        let text = "- [ ] "
        let action = resolve(text, caret: 6)
        #expect(singleRange(action) == NSRange(location: 0, length: 6))
        #expect(applied(action, to: text).isEmpty)
    }

    @Test("Nested task keeps its indent; only the marker run is deleted")
    func nestedTaskKeepsIndent() {
        let text = "  - [ ] item"
        let action = resolve(text, caret: 8) // after "  - [ ] "
        #expect(singleRange(action) == NSRange(location: 2, length: 6))
        #expect(applied(action, to: text) == "  item")
    }

    @Test("Heading prefix deleted at content start")
    func headingPrefixDeleted() {
        let text = "## Title"
        let action = resolve(text, caret: 3) // after "## "
        #expect(singleRange(action) == NSRange(location: 0, length: 3))
        #expect(applied(action, to: text) == "Title")
    }

    @Test("Bullet list prefix deleted, indent preserved")
    func bulletPrefixDeletedKeepsIndent() {
        let text = "  - item"
        let action = resolve(text, caret: 4) // after "  - "
        #expect(singleRange(action) == NSRange(location: 2, length: 2))
        #expect(applied(action, to: text) == "  item")
    }

    @Test("Ordered list prefix deleted, indent preserved")
    func orderedPrefixDeletedKeepsIndent() {
        let text = "  1. item"
        let action = resolve(text, caret: 5) // after "  1. "
        #expect(singleRange(action) == NSRange(location: 2, length: 3))
        #expect(applied(action, to: text) == "  item")
    }

    @Test("Blockquote prefix deleted")
    func blockquotePrefixDeleted() {
        let text = "> quote"
        let action = resolve(text, caret: 2) // after "> "
        #expect(singleRange(action) == NSRange(location: 0, length: 2))
        #expect(applied(action, to: text) == "quote")
    }

    @Test("Caret inside the prefix run stays characterwise (mid-marker escape hatch)")
    func midPrefixIsCharacterwise() {
        // Caret between "- [" and " ]" — a deliberate raw-edit posture.
        #expect(resolve("- [ ] task", caret: 3) == .characterwise)
    }

    // MARK: - R2: Inline pairs

    @Test("Bold unwraps: both runs deleted, content kept")
    func boldUnwraps() {
        let text = "**bold**"
        let action = resolve(text, caret: 8) // after closing **
        #expect(action == .ranges([NSRange(location: 6, length: 2), NSRange(location: 0, length: 2)]))
        #expect(applied(action, to: text) == "bold")
    }

    @Test("Italic unwraps")
    func italicUnwraps() {
        let text = "*x*"
        let action = resolve(text, caret: 3)
        #expect(applied(action, to: text) == "x")
    }

    @Test("Inline code pair unwraps")
    func inlineCodeUnwraps() {
        let text = "`code`"
        let action = resolve(text, caret: 6)
        #expect(applied(action, to: text) == "code")
    }

    @Test("Inline math pair unwraps")
    func inlineMathUnwraps() {
        let text = "$x+1$"
        let action = resolve(text, caret: 5)
        #expect(applied(action, to: text) == "x+1")
    }

    @Test("Strikethrough unwraps")
    func strikethroughUnwraps() {
        let text = "~~gone~~"
        let action = resolve(text, caret: 8)
        #expect(applied(action, to: text) == "gone")
    }

    @Test("Caret inside a pair's content stays characterwise")
    func midPairContentIsCharacterwise() {
        #expect(resolve("**bold**", caret: 4) == .characterwise)
    }

    // MARK: - R3: Bracketed inlines

    @Test("Link unwraps to its label")
    func linkUnwrapsToLabel() {
        let text = "[label](https://example.com)"
        let action = resolve(text, caret: (text as NSString).length) // after ")"
        #expect(applied(action, to: text) == "label")
    }

    @Test("Image unwraps to its alt text")
    func imageUnwrapsToAlt() {
        let text = "![alt](https://example.com/x.png)"
        let action = resolve(text, caret: (text as NSString).length)
        #expect(applied(action, to: text) == "alt")
    }

    @Test("Reference link unwraps to its visible text")
    func referenceLinkUnwraps() {
        let text = "[text][ref]"
        let action = resolve(text, caret: (text as NSString).length)
        #expect(applied(action, to: text) == "text")
    }

    @Test("Footnote reference unwraps to its id")
    func footnoteReferenceUnwraps() {
        let text = "see[^1]"
        let action = resolve(text, caret: (text as NSString).length) // after "]"
        #expect(applied(action, to: text) == "see1")
    }

    @Test("Autolink deletes the whole token (its text is the URL)")
    func autolinkDeletesWholeToken() {
        let text = "https://example.com"
        let action = resolve(text, caret: (text as NSString).length)
        #expect(singleRange(action) == NSRange(location: 0, length: (text as NSString).length))
        #expect(applied(action, to: text).isEmpty)
    }

    // MARK: - R4: Whole-line markers

    @Test("Horizontal rule line deleted, including its newline")
    func horizontalRuleLineDeleted() {
        let text = "---\nnext"
        let action = resolve(text, caret: 3) // at end of "---"
        #expect(singleRange(action) == NSRange(location: 0, length: 4)) // incl "\n"
        #expect(applied(action, to: text) == "next")
    }

    @Test("Code fence opening line deleted, including its newline")
    func codeFenceLineDeleted() {
        let text = "```\ncode\n```\n"
        let action = resolve(text, caret: 3) // end of opening ```
        #expect(applied(action, to: text) == "code\n```\n")
    }

    // MARK: - R5: Forward-delete mirrors

    @Test("Forward-delete at line start removes the task prefix")
    func forwardDeleteRemovesPrefix() {
        let text = "- [ ] asdsad"
        let action = resolve(text, caret: 0, direction: .forward)
        #expect(singleRange(action) == NSRange(location: 0, length: 6))
        #expect(applied(action, to: text) == "asdsad")
    }

    @Test("Forward-delete before an opening run unwraps the pair")
    func forwardDeleteUnwrapsPair() {
        let text = "**bold**"
        let action = resolve(text, caret: 0, direction: .forward)
        #expect(applied(action, to: text) == "bold")
    }

    @Test("Forward-delete at HR line start deletes the whole line")
    func forwardDeleteHorizontalRule() {
        let text = "---\nnext"
        let action = resolve(text, caret: 0, direction: .forward)
        #expect(applied(action, to: text) == "next")
    }

    // MARK: - Universal: selection, bounds

    @Test("A non-empty selection is always characterwise")
    func selectionIsCharacterwise() {
        let tokens = tokenizer.tokenize("**bold**")
        let action = DeletionIntent.resolve(
            text: "**bold**" as NSString,
            tokens: tokens,
            caret: NSRange(location: 2, length: 4),
            direction: .backward
        )
        #expect(action == .characterwise)
    }

    @Test("Backspace at document start is characterwise")
    func backspaceAtDocStart() {
        #expect(resolve("# Title", caret: 0) == .characterwise)
    }

    @Test("Forward-delete at document end is characterwise")
    func forwardDeleteAtDocEnd() {
        let text = "# Title"
        #expect(resolve(text, caret: (text as NSString).length, direction: .forward) == .characterwise)
    }

    @Test("Plain paragraph text is always characterwise")
    func plainTextIsCharacterwise() {
        #expect(resolve("just words", caret: 5) == .characterwise)
    }

    // MARK: - Caret placement

    @Test("Backspace caret lands at the deletion point")
    func backwardCaretLandsAtDeletionPoint() {
        // "**bold**" caret at 8 → unwrap → caret after "bold" at 4.
        let ranges = [NSRange(location: 6, length: 2), NSRange(location: 0, length: 2)]
        #expect(DeletionIntent.caretAfterDeletion(ranges: ranges, from: 8, direction: .backward) == 4)
    }

    @Test("Forward-delete leaves the caret in place")
    func forwardCaretStays() {
        let ranges = [NSRange(location: 0, length: 6)]
        #expect(DeletionIntent.caretAfterDeletion(ranges: ranges, from: 0, direction: .forward) == 0)
    }

    // MARK: - No-broken-syntax invariant

    @Test("Unwrapping a pair leaves no orphan markers when re-tokenized")
    func unwrapLeavesNoOrphanMarkers() {
        let text = "**bold**"
        let action = resolve(text, caret: 8)
        let result = applied(action, to: text)
        let tokens = tokenizer.tokenize(result)
        #expect(!tokens.contains { $0.type == .bold })
        #expect(result == "bold")
    }
}
