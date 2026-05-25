import Foundation
@testable import Pulp
import Testing

@Suite("ContentAnalyzer")
struct ContentAnalyzerTests {
    @Test func titleFromH1Heading() {
        let title = ContentAnalyzer.extractTitle(from: "# My Title\nSome body text")
        #expect(title == "My Title")
    }

    @Test func titleFromPlainFirstLine() {
        let title = ContentAnalyzer.extractTitle(from: "Just a plain line\nMore text")
        #expect(title == "Just a plain line")
    }

    @Test func titleFromEmptyDocument() {
        let title = ContentAnalyzer.extractTitle(from: "")
        #expect(title.isEmpty)
    }

    @Test func titleTrimsWhitespace() {
        let title = ContentAnalyzer.extractTitle(from: "#   Spaced Title  ")
        #expect(title == "Spaced Title")
    }

    @Test func tagsExtracted() {
        let tags = ContentAnalyzer.extractTags(from: "Hello #project and #ideas here")
        #expect(tags == ["project", "ideas"])
    }

    @Test func tagsNotFromCodeBlocks() {
        let text = """
        Some text
        ```
        #not_a_tag
        ```
        Real #tag here
        """
        let tags = ContentAnalyzer.extractTags(from: text)
        #expect(tags == ["tag"])
    }

    @Test func tagsNotFromInlineCode() {
        let tags = ContentAnalyzer.extractTags(from: "Use `#not_a_tag` but #real is")
        #expect(tags == ["real"])
    }

    @Test func nestedTags() {
        let tags = ContentAnalyzer.extractTags(from: "Check #work/meetings for details")
        #expect(tags == ["work/meetings"])
    }

    @Test func noDuplicateTags() {
        let tags = ContentAnalyzer.extractTags(from: "Tag #project and again #project")
        #expect(tags == ["project"])
    }

    @Test func headingMarkerNotTag() {
        let tags = ContentAnalyzer.extractTags(from: "# Heading\n#not a tag at line start")
        #expect(tags.isEmpty)
    }

    @Test func hasUncheckedTodos() {
        #expect(ContentAnalyzer.hasUncheckedTodos(in: "- [ ] task"))
        #expect(!ContentAnalyzer.hasUncheckedTodos(in: "- [x] done"))
        #expect(!ContentAnalyzer.hasUncheckedTodos(in: "no tasks here"))
    }
}
