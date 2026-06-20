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

    @Test func headingWithSpaceIsNotATag() {
        // `# `/`## ` (space after the hashes) are headings, never tags...
        #expect(ContentAnalyzer.extractTags(from: "# Heading\nbody").isEmpty)
        #expect(ContentAnalyzer.extractTags(from: "## Section only").isEmpty)
    }

    @Test func tagAtLineStartIsExtracted() {
        // ...but a `#tag` (letter after `#`) at a line/document start is a tag.
        #expect(ContentAnalyzer.extractTags(from: "# Heading\n#not a tag at line start") == ["not"])
        #expect(ContentAnalyzer.extractTags(from: "#first thing\nbody") == ["first"])
    }

    @Test func titleSkipsLeadingTable() {
        let text = "| Column 1 | Column 2 |\n| --- | --- |\n| a | b |\n\n# Real Title"
        #expect(ContentAnalyzer.extractTitle(from: text) == "Real Title")
    }

    @Test func titleSkipsLeadingBlankLines() {
        #expect(ContentAnalyzer.extractTitle(from: "\n\n  Actual line") == "Actual line")
    }

    @Test func hasUncheckedTodos() {
        #expect(ContentAnalyzer.hasUncheckedTodos(in: "- [ ] task"))
        #expect(!ContentAnalyzer.hasUncheckedTodos(in: "- [x] done"))
        #expect(!ContentAnalyzer.hasUncheckedTodos(in: "no tasks here"))
    }
}
