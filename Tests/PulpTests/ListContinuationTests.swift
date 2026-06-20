import Foundation
@testable import Pulp
import Testing

/// Return on a list line continues the list (carrying the marker + indent) or, on
/// an empty item, ends it. Regression coverage for ordered lists, which never
/// continued.
@Suite("ListContinuation")
struct ListContinuationTests {
    // MARK: - Ordered lists (the reported gap)

    @Test func orderedListContinuesWithNextNumber() {
        #expect(ListContinuation.outcome(forLine: "1. asdasda") == .continueItem("\n2. "))
        #expect(ListContinuation.outcome(forLine: "2. second") == .continueItem("\n3. "))
        #expect(ListContinuation.outcome(forLine: "9. ninth") == .continueItem("\n10. "))
    }

    @Test func orderedListCarriesIndent() {
        #expect(ListContinuation.outcome(forLine: "  3. nested") == .continueItem("\n  4. "))
    }

    @Test func emptyOrderedItemExits() {
        #expect(ListContinuation.outcome(forLine: "1. ") == .exitList)
        #expect(ListContinuation.outcome(forLine: "  2. ") == .exitList)
    }

    // MARK: - Bullets and tasks still work

    @Test func bulletListContinues() {
        #expect(ListContinuation.outcome(forLine: "- item") == .continueItem("\n- "))
        #expect(ListContinuation.outcome(forLine: "* item") == .continueItem("\n* "))
        #expect(ListContinuation.outcome(forLine: "  + nested") == .continueItem("\n  + "))
    }

    @Test func emptyBulletExits() {
        #expect(ListContinuation.outcome(forLine: "- ") == .exitList)
    }

    @Test func taskItemContinuesUnchecked() {
        #expect(ListContinuation.outcome(forLine: "- [ ] todo") == .continueItem("\n- [ ] "))
        // A checked item continues as a fresh unchecked one.
        #expect(ListContinuation.outcome(forLine: "- [x] done") == .continueItem("\n- [ ] "))
    }

    @Test func emptyTaskExits() {
        #expect(ListContinuation.outcome(forLine: "- [ ] ") == .exitList)
    }

    @Test func taskWinsOverBulletGrammar() {
        // `- [ ] ` must be read as a task, not a `- ` bullet whose text is `[ ]`.
        #expect(ListContinuation.outcome(forLine: "- [ ] x") == .continueItem("\n- [ ] "))
    }

    // MARK: - Non-list lines

    @Test func plainTextIsNotAList() {
        #expect(ListContinuation.outcome(forLine: "just text") == .notInList)
        #expect(ListContinuation.outcome(forLine: "") == .notInList)
        // A heading is not a continued list.
        #expect(ListContinuation.outcome(forLine: "# Title") == .notInList)
    }
}
