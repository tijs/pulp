import Foundation

/// What pressing Return on a line should do to continue (or end) a list. Computed
/// without any AppKit so it is unit-testable; the macOS text view maps the
/// outcome to an actual edit.
public enum ListNewlineOutcome: Equatable {
    /// Not a list line — let the text view insert a plain newline.
    case notInList
    /// Return on an *empty* list item: clear the marker and end the list.
    case exitList
    /// Continue the list — insert this text (a newline + the next marker) at the
    /// caret, e.g. `"\n2. "`, `"\n- "`, or `"\n- [ ] "`.
    case continueItem(String)
}

/// Decides how Return continues a Markdown list. Task items, ordered lists, and
/// bullet lists each carry their marker (and indentation) onto the next line;
/// an empty item ends the list. Mirrors the marker grammar the tokenizer uses
/// (`MarkdownTokenizer+Block`).
enum ListContinuation {
    static func outcome(forLine line: String) -> ListNewlineOutcome {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Task items first: `- [ ] ` also matches the bullet grammar, so it must
        // win over it.
        if let match = taskRegex.firstMatch(in: line, range: full) {
            let indent = ns.substring(with: match.range(at: 1))
            return isEmpty(line, afterMarker: "^\\s*- \\[[ xX]\\] ")
                ? .exitList
                : .continueItem("\n\(indent)- [ ] ")
        }

        // Ordered list: carry the indent and the *next* number.
        if let match = orderedRegex.firstMatch(in: line, range: full) {
            let indent = ns.substring(with: match.range(at: 1))
            let number = Int(ns.substring(with: match.range(at: 2))) ?? 1
            return isEmpty(line, afterMarker: "^\\s*\\d+\\. ")
                ? .exitList
                : .continueItem("\n\(indent)\(number + 1). ")
        }

        // Bullet list: carry the same bullet character.
        if let match = bulletRegex.firstMatch(in: line, range: full) {
            let indent = ns.substring(with: match.range(at: 1))
            let bullet = ns.substring(with: match.range(at: 2))
            return isEmpty(line, afterMarker: "^\\s*[-*+] ")
                ? .exitList
                : .continueItem("\n\(indent)\(bullet) ")
        }

        return .notInList
    }

    /// Whether the line has no content after its block marker (so Return should
    /// end the list rather than add another empty item).
    private static func isEmpty(_ line: String, afterMarker pattern: String) -> Bool {
        line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // swiftlint:disable force_try
    private static let taskRegex = try! NSRegularExpression(pattern: "^(\\s*)- \\[[ xX]\\] ")
    private static let orderedRegex = try! NSRegularExpression(pattern: "^(\\s*)(\\d+)\\. ")
    private static let bulletRegex = try! NSRegularExpression(pattern: "^(\\s*)([-*+]) ")
    // swiftlint:enable force_try
}
