import Foundation

public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacementText: String

    public init(range: NSRange, replacementText: String) {
        self.range = range
        self.replacementText = replacementText
    }

    public var position: Int {
        range.location
    }

    public var deleteCount: Int {
        range.length
    }

    public var isInsertion: Bool {
        range.length == 0 && !replacementText.isEmpty
    }

    public var isDeletion: Bool {
        !replacementText.isEmpty == false && range.length > 0
    }
}
