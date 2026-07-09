#if canImport(AppKit)
import AppKit
@testable import Pulp
import Testing

/// Regression: the editor's document view must track the scroll view's width
/// explicitly. Binaries linked against older SDKs (CI release builds) get no
/// implicit width tracking from AppKit, so a zero-width document view laid the
/// whole note out in a 0pt column and the editor rendered blank while the text
/// was demonstrably present (kiem-app v0.1.0-alpha.10, 2026-07-09).
@MainActor
@Suite("EditorLayout")
struct EditorLayoutTests {
    @Test func documentViewTracksScrollViewWidth() {
        let view = PulpNSTextView()
        view.setText("# Title\n\nSome body text long enough to lay out.")

        view.setFrameSize(NSSize(width: 500, height: 400))
        view.layoutSubtreeIfNeeded()
        view.layout()

        #expect(view.textView.frame.width == 500)
    }

    @Test func documentViewFollowsResize() {
        let view = PulpNSTextView()
        view.setText("body")
        view.setFrameSize(NSSize(width: 500, height: 400))
        view.layoutSubtreeIfNeeded()
        view.layout()

        view.setFrameSize(NSSize(width: 320, height: 400))
        view.layoutSubtreeIfNeeded()
        view.layout()

        #expect(view.textView.frame.width == 320)
    }

    /// The frame checks above pass vacuously on toolchains whose AppKit
    /// auto-tracks the clip view width (macOS 26 SDK), so also pin the
    /// explicit configuration that older-SDK builds depend on.
    @Test func documentViewIsConfiguredForWidthTracking() {
        let view = PulpNSTextView()
        #expect(view.textView.autoresizingMask.contains(.width))
        #expect(view.textView.maxSize.width == CGFloat.greatestFiniteMagnitude)
        #expect(view.textView.textContainer?.widthTracksTextView == true)
    }
}
#endif
