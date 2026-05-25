import Foundation
@testable import Pulp
import Testing

@Test func textEditProperties() {
    let insert = TextEdit(range: NSRange(location: 5, length: 0), replacementText: "hello")
    #expect(insert.position == 5)
    #expect(insert.deleteCount == 0)
    #expect(insert.isInsertion == true)

    let delete = TextEdit(range: NSRange(location: 3, length: 4), replacementText: "")
    #expect(delete.position == 3)
    #expect(delete.deleteCount == 4)
}

@Test func markdownTokenTypes() {
    let heading = MarkdownToken(
        type: .heading(level: 1),
        range: NSRange(location: 0, length: 7),
        markerRanges: [NSRange(location: 0, length: 2)]
    )
    #expect(heading.type == .heading(level: 1))
    #expect(heading.markerRanges.count == 1)
}

@Test func defaultTheme() {
    let theme = PulpTheme.default
    #expect(theme.headingSizes.count == 6)
    #expect(theme.markerShrinkSize < 1.0)
    #expect(theme.bodySize == 16)
}
