#if canImport(AppKit)
import AppKit
@testable import Pulp
import Testing

/// Geometry checks for nested list/checklist marker alignment. These run headless
/// (no window) via `layoutForTesting`, which is the reliable way to verify the
/// custom-drawn bullets/checkboxes — synthetic UI events do not drive this view.
@Suite("Nested list layout")
@MainActor
struct NestedListLayoutTests {
    private func makeEditor(_ text: String) -> PulpNSTextView {
        let view = PulpNSTextView()
        view.setText(text)
        view.layoutForTesting(height: 2000)
        return view
    }

    @Test func bulletsIndentWithDepth() {
        let view = makeEditor("- a\n  - b\n    - c\n")
        let bullets = view.bulletItemsForTesting
        #expect(bullets.count == 3)
        // Each deeper level's bullet sits further right than the one above it.
        #expect(bullets[0].rect.minX < bullets[1].rect.minX)
        #expect(bullets[1].rect.minX < bullets[2].rect.minX)
    }

    @Test func bulletGlyphCyclesByDepth() {
        let view = makeEditor("- a\n  - b\n    - c\n")
        let bullets = view.bulletItemsForTesting
        #expect(bullets[0].style == .filledDot)
        #expect(bullets[1].style == .ring)
        #expect(bullets[2].style == .diamond)
    }

    @Test func bulletDepthStepMatchesTextIndentStep() {
        // The glyph's horizontal shift per nesting level must equal the text's
        // per-level indent step, so the marker stays the same distance left of
        // its text at every depth. (Absolute minX includes the container origin,
        // so we assert on the deltas, which are origin-independent.)
        let view = makeEditor("- a\n  - b\n    - c\n")
        let bullets = view.bulletItemsForTesting
        let step = MarkdownStyler.listIndentStep
        #expect(abs((bullets[1].rect.minX - bullets[0].rect.minX) - step) < 0.5)
        #expect(abs((bullets[2].rect.minX - bullets[1].rect.minX) - step) < 0.5)
    }

    @Test func emptyTaskItemKeepsItsLineCheckboxesDoNotOverlap() {
        // Enter after a task item continues the list with an empty "- [ ] "
        // line. That line is all marker; shrinking must not collapse it,
        // or its checkbox draws on top of the neighbor's.
        let view = makeEditor("- [ ] some task list\n- [ ] ")
        let boxes = view.checkboxItemsForTesting
        #expect(boxes.count == 2)
        if boxes.count == 2 {
            #expect(!boxes[0].rect.intersects(boxes[1].rect))
            // The empty item's box sits a full line below, not beside.
            #expect(boxes[1].rect.minY >= boxes[0].rect.maxY - 1)
        }
    }

    @Test func emptyBulletItemKeepsItsLineBulletsDoNotOverlap() {
        let view = makeEditor("- some item\n- ")
        let bullets = view.bulletItemsForTesting
        #expect(bullets.count == 2)
        if bullets.count == 2 {
            #expect(!bullets[0].rect.intersects(bullets[1].rect))
            #expect(bullets[1].rect.minY >= bullets[0].rect.maxY - 1)
        }
    }

    @Test func checkboxesIndentWithDepth() {
        let view = makeEditor("- [ ] a\n  - [x] b\n    - [ ] c\n")
        let boxes = view.checkboxItemsForTesting
        #expect(boxes.count == 3)
        #expect(boxes[0].rect.minX < boxes[1].rect.minX)
        #expect(boxes[1].rect.minX < boxes[2].rect.minX)
    }

    @Test func checkboxDepthStepMatchesBulletStep() {
        // Checkboxes must shift per level by the same step as bullets, so checklist
        // nesting aligns identically to bullet-list nesting.
        let view = makeEditor("- [ ] a\n  - [ ] b\n    - [ ] c\n")
        let boxes = view.checkboxItemsForTesting
        let step = MarkdownStyler.listIndentStep
        #expect(abs((boxes[1].rect.minX - boxes[0].rect.minX) - step) < 0.5)
        #expect(abs((boxes[2].rect.minX - boxes[1].rect.minX) - step) < 0.5)
    }
}
#endif
