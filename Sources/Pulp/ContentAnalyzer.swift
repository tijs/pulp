import Foundation

public enum ContentAnalyzer {
    /// Normalize line endings to LF. Swift treats `\r\n` as a single grapheme,
    /// so without this `split(separator: "\n")` and `pear-core` (which splits on
    /// the LF byte) would derive different titles for CRLF input. Both sides
    /// normalize first to stay in lockstep.
    private static func normalizingNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    public static func extractTitle(from text: String) -> String {
        let text = normalizingNewlines(text)
        // First non-empty line that isn't table/structural markup.
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("|") { continue } // table row
            if line.allSatisfy({ $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }) { continue }
            var title = line
            if title.hasPrefix("# ") {
                title = String(title.dropFirst(2))
            }
            return title.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    public static func extractTags(from text: String) -> [String] {
        let text = normalizingNewlines(text)
        let pattern = "(?<=\\s|^)#([a-zA-Z][a-zA-Z0-9_/]*)"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .anchorsMatchLines
        ) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )

        let excludedRanges = codeRanges(in: text, nsText: nsText)

        var tags: [String] = []
        for match in matches {
            let tagRange = match.range(at: 0)
            if isExcluded(tagRange, by: excludedRanges) { continue }

            let lineStart = nsText.lineRange(
                for: NSRange(location: tagRange.location, length: 0)
            ).location
            if tagRange.location == lineStart { continue }

            let tag = nsText.substring(with: match.range(at: 1))
            if !tags.contains(tag) {
                tags.append(tag)
            }
        }
        return tags
    }

    public static func hasUncheckedTodos(in text: String) -> Bool {
        text.contains("- [ ]")
    }

    private static func codeRanges(in text: String, nsText: NSString) -> [NSRange] {
        let fullRange = NSRange(location: 0, length: nsText.length)

        let codeBlockPattern = "(?m)^(`{3,}|~{3,})[^\\n]*\\n[\\s\\S]*?^\\1\\s*$"
        let codeRanges = (try? NSRegularExpression(
            pattern: codeBlockPattern,
            options: .anchorsMatchLines
        ))?.matches(in: text, range: fullRange).map(\.range) ?? []

        let inlineCodePattern = "`[^`]+`"
        let inlineRanges = (try? NSRegularExpression(
            pattern: inlineCodePattern
        ))?.matches(in: text, range: fullRange).map(\.range) ?? []

        return codeRanges + inlineRanges
    }

    private static func isExcluded(_ range: NSRange, by excludedRanges: [NSRange]) -> Bool {
        excludedRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }
}
