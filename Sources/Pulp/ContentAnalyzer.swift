import Foundation

public enum ContentAnalyzer {
    public static func extractTitle(from text: String) -> String {
        guard let firstLine = text.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first else {
            return ""
        }
        var title = String(firstLine)
        if title.hasPrefix("# ") {
            title = String(title.dropFirst(2))
        }
        return title.trimmingCharacters(in: .whitespaces)
    }

    public static func extractTags(from text: String) -> [String] {
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
