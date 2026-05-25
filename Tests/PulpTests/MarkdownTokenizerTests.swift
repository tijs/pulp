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
}
