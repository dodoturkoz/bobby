import Foundation

/// A source edit suitable for NSTextView's native, undoable insertText API.
/// Construction requires the exact original line, including its whitespace.
public struct SuggestionLineEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    public static func make(in text: String, lineIndex: Int, expectedLine: String,
                            expression: String) -> SuggestionLineEdit? {
        guard lineIndex >= 0, expression.rangeOfCharacter(from: .newlines) == nil else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex), lines[lineIndex] == expectedLine else { return nil }

        let rawLine = lines[lineIndex]
        let carriageReturn = rawLine.hasSuffix("\r") ? "\r" : ""
        let sourceLine = carriageReturn.isEmpty ? rawLine : String(rawLine.dropLast())
        let prefix = assignmentPrefix(in: sourceLine) ?? ""
        let location = lines.prefix(lineIndex).reduce(0) { $0 + $1.utf16.count + 1 }
        return SuggestionLineEdit(range: NSRange(location: location, length: rawLine.utf16.count),
                                  replacement: prefix + expression + carriageReturn)
    }

    private static func assignmentPrefix(in line: String) -> String? {
        // Match the engine's Unicode identifier and single assignment delimiter.
        // Leading indentation belongs to the prefix because the engine trims it
        // before recognizing an assignment. Restrict whitespace to the line.
        let pattern = #"^[^\S\r\n]*[\p{L}_][\p{L}\p{N}_]*[^\S\r\n]*=[^\S\r\n]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range, in: line) else { return nil }
        return String(line[range])
    }
}
