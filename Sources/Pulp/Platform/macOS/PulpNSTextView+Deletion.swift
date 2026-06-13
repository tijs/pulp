#if canImport(AppKit)
import AppKit
import Foundation

/// macOS wiring for the marker-atom deletion model. The platform-agnostic
/// decision logic lives in `DeletionIntent`; this extension routes ⌫ / fn⌫
/// through it and applies the result as one grouped, undoable edit.
extension PulpNSTextView {
    /// Route ⌫ / fn⌫ through the marker-atom resolver. Returns true (and performs
    /// a single grouped, undoable edit) when the caret sits on a marker boundary;
    /// returns false to let `NSTextView` do its normal one-character delete.
    ///
    /// Bails to default behavior while marked text (IME composition) is active or
    /// a table cell editor is open — those edit paths own their own deletion.
    func handleDeletion(_ textView: NSTextView, direction: DeletionDirection) -> Bool {
        guard cellEditor == nil, !textView.hasMarkedText() else { return false }

        let action = DeletionIntent.resolve(
            text: textView.string as NSString,
            tokens: cachedTokens,
            caret: textView.selectedRange(),
            direction: direction
        )

        switch action {
        case .characterwise:
            return false
        case let .ranges(ranges):
            applyAtomicDeletion(ranges, direction: direction, in: textView)
            return true
        }
    }

    /// Apply `ranges` (descending, non-overlapping) as one undoable edit and place
    /// the caret at the deletion point. `breakUndoCoalescing` keeps this off the
    /// preceding typing's undo group, so one ⌘Z restores the deleted element
    /// exactly. The grouped `shouldChangeText(inRanges:…)`/`didChangeText` pair is
    /// what registers that single undo step; the text-storage delegate's own echo
    /// then reports the net change to the consumer binding.
    private func applyAtomicDeletion(_ ranges: [NSRange], direction: DeletionDirection, in textView: NSTextView) {
        guard !ranges.isEmpty, let textStorage = textView.textStorage else { return }

        let caret = DeletionIntent.caretAfterDeletion(
            ranges: ranges,
            from: textView.selectedRange().location,
            direction: direction
        )

        textView.breakUndoCoalescing()
        let nsRanges = ranges.map { NSValue(range: $0) }
        let replacements = [String](repeating: "", count: ranges.count)
        guard textView.shouldChangeText(inRanges: nsRanges, replacementStrings: replacements) else { return }

        textStorage.beginEditing()
        for range in ranges { // descending order — earlier deletions don't shift later ones
            textStorage.replaceCharacters(in: range, with: "")
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: caret, length: 0))
    }

    // MARK: - Verification Seam

    /// Drive a ⌫ / fn⌫ keypress through the same path the delegate takes, then
    /// refresh tokens synchronously (the run loop's async restyle isn't pumped in
    /// tests). Falls back to the platform's characterwise delete when the resolver
    /// declines, so tests can assert that branch too. Returns whether the
    /// marker-atom path handled it.
    @discardableResult
    func deleteForTesting(_ direction: DeletionDirection) -> Bool {
        let handled = textView(textView, doCommandBy: direction == .backward
            ? #selector(NSResponder.deleteBackward(_:))
            : #selector(NSResponder.deleteForward(_:)))
        if !handled {
            switch direction {
            case .backward: textView.deleteBackward(nil)
            case .forward: textView.deleteForward(nil)
            }
        }
        restyleAll()
        return handled
    }
}
#endif
