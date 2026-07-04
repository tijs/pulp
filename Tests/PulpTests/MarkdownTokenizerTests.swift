import Foundation
@testable import Pulp
import Testing

@Suite("MarkdownTokenizer")
struct MarkdownTokenizerTests {
    let tokenizer = MarkdownTokenizer()

    @Test func headingH1() {
        let tokens = tokenizer.tokenize("# Hello World")
        let headings = tokens.filter { if case .heading = $0.type { return true }
            return false
        }
        #expect(headings.count == 1)
        if case let .heading(level) = headings[0].type {
            #expect(level == 1)
        }
        #expect(headings[0].markerRanges.count == 1)
    }

    @Test func headingH3() {
        let tokens = tokenizer.tokenize("### Third level")
        let headings = tokens.filter { if case .heading = $0.type { return true }
            return false
        }
        #expect(headings.count == 1)
        if case let .heading(level) = headings[0].type {
            #expect(level == 3)
        }
    }

    @Test func boldText() {
        let tokens = tokenizer.tokenize("some **bold** text")
        let bolds = tokens.filter { $0.type == .bold }
        #expect(bolds.count == 1)
        #expect(bolds[0].markerRanges.count == 2)
    }

    @Test func italicText() {
        let tokens = tokenizer.tokenize("some *italic* text")
        let italics = tokens.filter { $0.type == .italic }
        #expect(italics.count == 1)
        #expect(italics[0].markerRanges.count == 2)
    }

    /// A `*`-bulleted list item with italic content: `* *word*`. The bullet
    /// asterisk must NOT be treated as an emphasis delimiter — the italic span is
    /// `*word*`, leaving the list item intact. (Regression: previously the regex
    /// matched `* *` and the real italic never parsed.)
    @Test func italicInsideAsteriskBulletList() {
        let tokens = tokenizer.tokenize("* *word*")
        let italics = tokens.filter { $0.type == .italic }
        #expect(italics.count == 1)
        #expect(tokens.contains { $0.type == .listItem })
        // The italic span covers `*word*` (offset 2), not the bullet at offset 0.
        #expect(italics.first?.range == NSRange(location: 2, length: 6))
    }

    /// Flanking: an asterisk adjacent to whitespace is not a delimiter, so
    /// `* foo *` (spaces hugging the stars) is not italic.
    @Test func asteriskWithSurroundingSpacesIsNotItalic() {
        let tokens = tokenizer.tokenize("a * foo * b")
        #expect(!tokens.contains { $0.type == .italic })
    }

    @Test func boldItalicText() {
        let tokens = tokenizer.tokenize("some ***bolditalic*** text")
        let bi = tokens.filter { $0.type == .boldItalic }
        #expect(bi.count == 1)
    }

    @Test func inlineCode() {
        let tokens = tokenizer.tokenize("use `let x = 5` here")
        let codes = tokens.filter { $0.type == .inlineCode }
        #expect(codes.count == 1)
        #expect(codes[0].markerRanges.count == 2)
    }

    @Test func fencedCodeBlock() {
        let text = """
        ```swift
        let x = 5
        ```
        """
        let tokens = tokenizer.tokenize(text)
        let blocks = tokens.filter { $0.type == .codeBlock }
        #expect(blocks.count == 1)
    }

    @Test func leadingFrontmatterFenceIsOneToken() {
        let text = "---\nstatus: active\n---\n# Plan\nbody #tag"
        let tokens = tokenizer.tokenize(text)
        let frontmatter = tokens.filter { $0.type == .frontmatter }
        #expect(frontmatter.count == 1)
        // No stray horizontal rules for the fence lines, and the heading/tag
        // after the fence still tokenize normally.
        #expect(tokens.filter { $0.type == .horizontalRule }.isEmpty)
        #expect(tokens.contains { if case .heading = $0.type { return true }; return false })
        #expect(tokens.contains { $0.type == .hashtag })
    }

    @Test func leadingFrontmatterFenceSurvivesCRLF() {
        // A CRLF-saved fence must still tokenize as one `.frontmatter` block,
        // not silently fall back to two horizontal rules (the fence lines'
        // markerRanges must land on the `---` lines, not one char short/long
        // because of the extra `\r`).
        let text = "---\r\nstatus: active\r\n---\r\n# Plan\r\nbody #tag"
        let tokens = tokenizer.tokenize(text)
        let frontmatter = tokens.filter { $0.type == .frontmatter }
        #expect(frontmatter.count == 1)
        #expect(frontmatter[0].markerRanges.count == 2)
        #expect(tokens.filter { $0.type == .horizontalRule }.isEmpty)
        #expect(tokens.contains { if case .heading = $0.type { return true }; return false })
        #expect(tokens.contains { $0.type == .hashtag })
    }

    @Test func nonLeadingHorizontalRuleIsNotFrontmatter() {
        // A `---` fence anywhere but the very start of the document is an
        // ordinary horizontal rule, not frontmatter.
        let text = "Some prose\n\n---\n\nMore prose"
        let tokens = tokenizer.tokenize(text)
        #expect(tokens.filter { $0.type == .frontmatter }.isEmpty)
        #expect(tokens.contains { $0.type == .horizontalRule })
    }

    @Test func unterminatedFrontmatterFenceFallsBackToHorizontalRule() {
        let text = "---\nstatus: active\nno closing fence"
        let tokens = tokenizer.tokenize(text)
        #expect(tokens.filter { $0.type == .frontmatter }.isEmpty)
        #expect(tokens.contains { $0.type == .horizontalRule })
    }

    @Test func taskItemUnchecked() {
        let tokens = tokenizer.tokenize("- [ ] Buy milk")
        let tasks = tokens.filter { if case .taskItem = $0.type { return true }
            return false
        }
        #expect(tasks.count == 1)
        if case let .taskItem(checked) = tasks[0].type {
            #expect(checked == false)
        }
    }

    @Test func taskItemChecked() {
        let tokens = tokenizer.tokenize("- [x] Buy milk")
        let tasks = tokens.filter { if case .taskItem = $0.type { return true }
            return false
        }
        #expect(tasks.count == 1)
        if case let .taskItem(checked) = tasks[0].type {
            #expect(checked == true)
        }
    }

    @Test func hashtag() {
        let tokens = tokenizer.tokenize("Check out #project and #todo")
        let tags = tokens.filter { $0.type == .hashtag }
        #expect(tags.count == 2)
    }

    @Test func hashtagNotInCodeBlock() {
        let text = """
        ```
        #not_a_tag
        ```
        real #tag here
        """
        let tokens = tokenizer.tokenize(text)
        let tags = tokens.filter { $0.type == .hashtag }
        #expect(tags.count == 1)
    }

    @Test func hashtagNotHeadingMarker() {
        let tokens = tokenizer.tokenize("# Heading")
        let tags = tokens.filter { $0.type == .hashtag }
        #expect(tags.isEmpty)
    }

    /// A `#tag` at the start of a line (or the document) is a real tag — only a
    /// `#` *followed by a space* is a heading. Regression: line-start tags used
    /// to be skipped.
    @Test func hashtagAtLineStartIsTagged() {
        let text = "#hello\n\nSome #tag\n\n#world"
        let tags = tokenizer.tokenize(text).filter { $0.type == .hashtag }
        #expect(tags.count == 3)
    }

    @Test func hashtagAtDocumentStartIsTagged() {
        let tags = tokenizer.tokenize("#first thing").filter { $0.type == .hashtag }
        #expect(tags.count == 1)
        #expect(tags.first?.range == NSRange(location: 0, length: 6))
    }

    @Test func link() {
        let tokens = tokenizer.tokenize("Visit [Google](https://google.com) now")
        let links = tokens.filter { if case .link = $0.type { return true }
            return false
        }
        #expect(links.count == 1)
        if case let .link(url) = links[0].type {
            #expect(url == "https://google.com")
        }
    }

    @Test func blockquote() {
        let tokens = tokenizer.tokenize("> Some quoted text")
        let quotes = tokens.filter { $0.type == .blockquote }
        #expect(quotes.count == 1)
    }

    @Test func listItem() {
        let tokens = tokenizer.tokenize("- An item")
        let items = tokens.filter { $0.type == .listItem }
        #expect(items.count == 1)
    }

    @Test func multipleElements() {
        let text = """
        # Title
        Some **bold** and *italic* text
        - [ ] A task
        - [x] Done task
        Visit #project for more
        """
        let tokens = tokenizer.tokenize(text)
        let headings = tokens.filter { if case .heading = $0.type { return true }
            return false
        }
        let bolds = tokens.filter { $0.type == .bold }
        let italics = tokens.filter { $0.type == .italic }
        let unchecked = tokens.filter { $0.type == .taskItem(checked: false) }
        let checked = tokens.filter { $0.type == .taskItem(checked: true) }
        let tags = tokens.filter { $0.type == .hashtag }

        #expect(headings.count == 1)
        #expect(bolds.count == 1)
        #expect(italics.count == 1)
        #expect(unchecked.count == 1)
        #expect(checked.count == 1)
        #expect(tags.count == 1)
    }

    @Test func emptyString() {
        let tokens = tokenizer.tokenize("")
        #expect(tokens.isEmpty)
    }

    @Test func nestedHashtag() {
        let tokens = tokenizer.tokenize("See #work/meetings for details")
        let tags = tokens.filter { $0.type == .hashtag }
        #expect(tags.count == 1)
    }

    @Test func simpleTable() {
        let text = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let tokens = tokenizer.tokenize(text)
        let tables = tokens.filter { if case .table = $0.type { return true }
            return false
        }
        let headers = tokens.filter { $0.type == .tableHeaderRow }
        let separators = tokens.filter { $0.type == .tableSeparatorRow }
        let dataRows = tokens.filter { $0.type == .tableDataRow }

        #expect(tables.count == 1)
        #expect(headers.count == 1)
        #expect(separators.count == 1)
        #expect(dataRows.count == 1)

        if case let .table(columns) = tables[0].type {
            #expect(columns == 2)
        }
    }

    @Test func tableWithMultipleDataRows() {
        let text = """
        | Name | Score |
        |------|-------|
        | Alice | 95 |
        | Bob | 87 |
        | Carol | 92 |
        """
        let tokens = tokenizer.tokenize(text)
        let dataRows = tokens.filter { $0.type == .tableDataRow }
        #expect(dataRows.count == 3)
    }

    @Test func tableNotDetectedWithoutSeparator() {
        let text = """
        | Not a table |
        | Just pipes |
        """
        let tokens = tokenizer.tokenize(text)
        let tables = tokens.filter { if case .table = $0.type { return true }
            return false
        }
        #expect(tables.isEmpty)
    }

    @Test func tableInsideCodeBlockIgnored() {
        let text = """
        ```
        | A | B |
        |---|---|
        | 1 | 2 |
        ```
        """
        let tokens = tokenizer.tokenize(text)
        let tables = tokens.filter { if case .table = $0.type { return true }
            return false
        }
        #expect(tables.isEmpty)
    }
}
