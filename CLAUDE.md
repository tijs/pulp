# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**Pulp** is a standalone, open-source Swift package: an inline Markdown editor built on
**TextKit 1**. It is deliberately self-contained — no dependency on Rust, on Kiem, or on
any other app. Kiem (the sibling `../kiem-app` repo) is its first consumer, but Pulp must
stay independently shippable, so nothing Kiem-specific belongs in `Sources/Pulp`.

The Swift package is at the repo root (`Package.swift`, product `Pulp`). `PulpDemoApp/`
is an Xcode project that consumes the package locally for manual testing.

## Commands

```bash
swift test                                    # all tests (run from repo root)
swift test --filter MarkdownCoverageTests     # one suite
swift test --filter ContentFixtureTests/matchesSharedContract   # one test
swift build
swiftlint                                     # lint (.swiftlint.yml)
swiftlint --fix                               # autofix
swiftformat .                                 # format (.swiftformat)
```

Per the user's global setup, pipe Swift commands through `xcsift` for readable output,
e.g. `swift test | xcsift`. Use `swiftlint --fix` for lint issues. Use `debugPrint()`,
not `print()`.

The `PulpDemoApp/` Xcode project is excluded from swiftlint/swiftformat and from the
package test target.

## Architecture

The editor keeps the **full Markdown source in the text storage at all times** and renders
inline by restyling — it never converts to a separate rich model. Three stages:

1. **Tokenize** (`Sources/Pulp/Parsing/`): `MarkdownTokenizer` (+`Block`/`+Inline`
   extensions — split to stay under the file-size limit) scans text into `MarkdownToken`s
   (type + ranges + `markerRanges`). Tokenizing runs on **every keystroke over the whole
   document**, so keep regexes cheap and bounded (unbounded `[^x]+` classes have caused
   per-keystroke ReDoS; patterns are length-capped on purpose).
2. **Style** (`Sources/Pulp/Styling/MarkdownStyler.swift`): maps tokens to
   `NSAttributedString` runs. The core trick is **marker-shrinking** — syntax markers
   (`#`, `**`, `$`, etc.) are shrunk to near-invisible via `markerRanges`, and revealed on
   the cursor's line (selection-aware). Every hidden delimiter MUST be listed in a token's
   `markerRanges` or reveal breaks.
3. **Draw** (`Sources/Pulp/Platform/macOS/`): `PulpInternalTextView` (an NSTextView
   subclass) custom-draws what attributes can't — checkboxes, list-bullet dots, code-block
   backgrounds, and GFM tables (rendered as an overlay over invisible pipe source, not
   `NSTextAttachment`). `PulpNSTextView` is the public API class; `PulpEditorView` is the
   SwiftUI `NSViewRepresentable` wrapper.

`NSRange` is UTF-16 throughout; `tokenizeParagraph` shifts paragraph-local ranges by an
offset, so any new token must carry its ranges through that shift.

Public API surface: `PulpEditorProtocol`, `PulpEditorDelegate`, `PulpTheme`, `PulpPalette`,
`TextEdit`. `ContentAnalyzer` derives title/tags/todos (see contract below).

Platform: macOS (TextKit 1 / AppKit) is implemented; an iOS UITextView port is pending.
New rendering/UI code is macOS-specific and lives under `Platform/macOS/`; keep
platform-agnostic logic (parsing, styling-run computation) out of it so the iOS port can
reuse it. Guard AppKit-only APIs with `#if canImport(AppKit)` / `#elseif canImport(UIKit)`.

## The shared content-derivation contract

`ContentAnalyzer` (title/tags/unchecked-todos) is a **mirror** of an authoritative Rust
implementation in the sibling `../kiem-app` repo. Both must produce identical results.
`Tests/PulpTests/ContentFixtureTests.swift` runs `ContentAnalyzer` against a **vendored
copy** of the canonical fixtures at `Tests/PulpTests/Fixtures/content-derivation.json`
(declared as a `.process` resource so `Bundle.module` resolves it on iOS too).

If you change `ContentAnalyzer`'s rules, the change must also land in `kiem-app`'s Rust
`kiem-core` and in the canonical fixture file, then be re-vendored here. This repo's suite
only proves *its* copy is correct; it does not reach into the other repo.

## Theming

Pulp ships a **neutral default theme** and is branded by the consumer. Branding (e.g. the
demo app's `KiemTheme`) lives in the consuming app, never in `Sources/Pulp`. See
`STYLE_GUIDE.md` for the design-token system (no inline colors, no magic numbers; all
colors resolve light/dark via `PulpPalette`).

## Lint specifics worth knowing

`.swiftlint.yml` sets file-length warn/error at 500/700, type-body at 300/500, function-body
at 60/120, and enables `unused_declaration` (analyzer). `trailing_comma` and `todo` are
disabled. When a tokenizer/styler file approaches the limit, split it into a `+Extension`
file (as `MarkdownTokenizer` already is) rather than relaxing the rule.
