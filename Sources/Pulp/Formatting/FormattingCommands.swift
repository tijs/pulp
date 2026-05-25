#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

public extension PulpEditorProtocol {
    func toggleBold() {
        wrapSelection(prefix: "**", suffix: "**")
    }

    func toggleItalic() {
        wrapSelection(prefix: "*", suffix: "*")
    }

    func toggleStrikethrough() {
        wrapSelection(prefix: "~~", suffix: "~~")
    }

    func toggleHighlight() {
        wrapSelection(prefix: "==", suffix: "==")
    }

    func toggleInlineCode() {
        wrapSelection(prefix: "`", suffix: "`")
    }

    func setHeading(level: Int) {
        let prefix = String(repeating: "#", count: level) + " "
        replaceLinePrefix(with: prefix, pattern: "^#{1,6}\\s+")
    }

    func toggleTaskList() {
        toggleLinePrefix("- [ ] ")
    }

    func toggleUnorderedList() {
        toggleLinePrefix("- ")
    }

    func toggleBlockquote() {
        toggleLinePrefix("> ")
    }
}

private extension PulpEditorProtocol {
    func wrapSelection(prefix: String, suffix: String) {
        let sel = selectedRange
        let nsText = text as NSString
        guard sel.location != NSNotFound else { return }

        if sel.length == 0 {
            let insertText = "\(prefix)\(suffix)"
            applyTextReplacement(range: sel, replacement: insertText)
            selectedRange = NSRange(location: sel.location + prefix.count, length: 0)
            return
        }

        let selected = nsText.substring(with: sel)

        if selected.hasPrefix(prefix), selected.hasSuffix(suffix), selected.count > prefix.count + suffix.count {
            let start = selected.index(selected.startIndex, offsetBy: prefix.count)
            let end = selected.index(selected.endIndex, offsetBy: -suffix.count)
            let unwrapped = String(selected[start ..< end])
            applyTextReplacement(range: sel, replacement: unwrapped)
            selectedRange = NSRange(location: sel.location, length: unwrapped.count)
        } else {
            let wrapped = "\(prefix)\(selected)\(suffix)"
            applyTextReplacement(range: sel, replacement: wrapped)
            selectedRange = NSRange(location: sel.location + prefix.count, length: sel.length)
        }
    }

    func replaceLinePrefix(with newPrefix: String, pattern: String) {
        let nsText = text as NSString
        let sel = selectedRange
        guard sel.location <= nsText.length else { return }

        let lineRange = nsText.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = nsText.substring(with: lineRange)

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        {
            let existingPrefix = (line as NSString).substring(with: match.range)
            if existingPrefix == newPrefix {
                let removeRange = NSRange(location: lineRange.location, length: newPrefix.count)
                applyTextReplacement(range: removeRange, replacement: "")
                return
            }
            let replaceRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            applyTextReplacement(range: replaceRange, replacement: newPrefix)
        } else {
            applyTextReplacement(range: NSRange(location: lineRange.location, length: 0), replacement: newPrefix)
        }
    }

    func toggleLinePrefix(_ prefix: String) {
        let nsText = text as NSString
        let sel = selectedRange
        guard sel.location <= nsText.length else { return }

        let lineRange = nsText.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = nsText.substring(with: lineRange)

        if line.hasPrefix(prefix) {
            let removeRange = NSRange(location: lineRange.location, length: prefix.count)
            applyTextReplacement(range: removeRange, replacement: "")
        } else {
            applyTextReplacement(range: NSRange(location: lineRange.location, length: 0), replacement: prefix)
        }
    }

    func applyTextReplacement(range: NSRange, replacement: String) {
        let edit = TextEdit(range: range, replacementText: replacement)
        applyRemoteEdit(edit)
    }
}
