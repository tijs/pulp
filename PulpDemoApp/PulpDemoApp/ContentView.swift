import SwiftUI
import Pulp

struct ContentView: View {
    @State private var text = """
# Welcome to Pulp

An inline Markdown editor built as an open-source Swift Package. This document
showcases every element in Pulp's Markdown flavor.

## Text Formatting

Asterisk emphasis: **bold**, *italic*, and ***bold italic***.

Underscore emphasis also works: __bold__, _italic_, and ___bold italic___ — but
intra-word underscores are left alone, so `snake_case` and file_name_2 stay plain.

You can also use ~~strikethrough~~ for deleted text and ==highlighted text== for
emphasis with a colored background.

## Unordered Lists

- First item
- Second item with **bold** inside
- Nested levels indent by depth:
  - Second level
    - Third level
- Bullets can use `-`, `*`, or `+`

## Ordered Lists

1. First step
2. Second step
   1. Nested step
   2. Another nested step
3. Third step

## Task Lists

- [ ] Build the tokenizer
- [x] Set up the Swift Package
- [x] Implement marker shrinking
  - [x] Nested checked subtask
  - [ ] Nested unchecked subtask
- [ ] Add iOS support

## Code

Inline code like `let x = 5` gets a background. Fenced code blocks too:

```swift
struct Note {
    var title: String
    var body: String
    var tags: [String]
}
```

## Math

Inline math renders as a styled span (not typeset): $E = mc^2$ and $a_n + b_n$.
A `$5 and $10` price is left as plain text.

Block math spans multiple lines:

$$
\\int_0^1 f(x)\\,dx = F(1) - F(0)
$$

## Links, Images, and Tags

Inline link: visit [Pulp on GitHub](https://github.com/example/pulp).

Bare autolinks are detected too: https://swift.org and http://example.com.

Reference-style link: see [the Swift forums][forums] for discussion.

[forums]: https://forums.swift.org

An image: ![Pulp logo](https://example.com/logo.png)

Organize with #project and #ideas tags. Nested tags like #work/meetings work too.

A claim that needs a source.[^1]

[^1]: Footnotes render their marker and definition.

## Blockquotes

> Blockquotes get a subtle secondary color.
> They can span multiple lines.

## Tables

| Feature              | Status  | Priority |
|----------------------|---------|----------|
| Headings             | Done    | P0       |
| Bold/Italic          | Done    | P0       |
| Task Lists           | Done    | P0       |
| Tables               | New     | P1       |
| Syntax Highlighting  | Planned | P2       |

A second table with longer content:

| Name | Description                    | Rating |
|------|--------------------------------|--------|
| Pulp | Inline Markdown editor         | 5      |
| Kiem | P2P notes with CRDT sync       | 4      |
| Bear | Cloud-based notes app          | 5      |

## Horizontal Rules

Above the line.

---

Below the line.

## Headings

### H3 Heading
#### H4 Heading
##### H5 Heading
###### H6 Heading

Setext H1
=========

Setext H2
---------
"""

    @State private var derivedTitle = ""
    @State private var derivedTags: [String] = []
    @State private var hasTodos = false
    @StateObject private var controller = PulpEditorController()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            PulpEditorView(
                text: $text,
                theme: KiemTheme.theme,
                delegate: DemoDelegate(
                    onTitle: { derivedTitle = $0 },
                    onTags: { derivedTags = $0 },
                    onTodos: { hasTodos = $0 }
                ),
                controller: controller
            )
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            derivedTitle = ContentAnalyzer.extractTitle(from: text)
            derivedTags = ContentAnalyzer.extractTags(from: text)
            hasTodos = text.contains("- [ ]")
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(derivedTitle.isEmpty ? "Untitled" : derivedTitle)
                    .font(.headline)
                HStack(spacing: 6) {
                    ForEach(derivedTags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if hasTodos {
                        Text("Has todos")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            Spacer()
            Menu {
                Button("Insert Table (3×2)") { controller.insertTable(rows: 2, columns: 3) }
                Divider()
                Button("Insert Row Below") { controller.insertTableRowBelow() }
                Button("Insert Row Above") { controller.insertTableRowAbove() }
                Button("Insert Column Right") { controller.insertTableColumnRight() }
                Button("Insert Column Left") { controller.insertTableColumnLeft() }
                Divider()
                Button("Delete Row", role: .destructive) { controller.deleteTableRow() }
                Button("Delete Column", role: .destructive) { controller.deleteTableColumn() }
            } label: {
                Label("Table", systemImage: "tablecells")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

final class DemoDelegate: PulpEditorDelegate {
    let onTitle: (String) -> Void
    let onTags: ([String]) -> Void
    let onTodos: (Bool) -> Void

    init(
        onTitle: @escaping (String) -> Void,
        onTags: @escaping ([String]) -> Void,
        onTodos: @escaping (Bool) -> Void
    ) {
        self.onTitle = onTitle
        self.onTags = onTags
        self.onTodos = onTodos
    }

    func editor(_ editor: PulpEditorProtocol, didApplyEdit edit: TextEdit) {}
    func editor(_ editor: PulpEditorProtocol, didUpdateTitle title: String) { onTitle(title) }
    func editor(_ editor: PulpEditorProtocol, didUpdateTags tags: [String]) { onTags(tags) }
    func editor(_ editor: PulpEditorProtocol, didUpdateHasUncheckedTodos hasUncheckedTodos: Bool) { onTodos(hasUncheckedTodos) }
}

#Preview {
    ContentView()
}
