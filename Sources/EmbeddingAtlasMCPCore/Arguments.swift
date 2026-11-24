import Foundation

/// Typed access to a `tools/call` argument bag.
public struct Arguments {
    private let values: [String: Value]

    public init(_ values: [String: Value]?) {
        self.values = values ?? [:]
    }

    public func optionalString(_ name: String) -> String? {
        guard let text = values[name]?.stringValue else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func requiredString(_ name: String) throws -> String {
        guard let text = optionalString(name) else { throw ToolError.missingArgument(name) }
        return text
    }

    /// Rejects rather than clamps: a port one off from the one asked for is another server.
    public func int(_ name: String, default fallback: Int, in range: ClosedRange<Int>) throws
        -> Int
    {
        guard let raw = values[name] else { return fallback }
        if case .null = raw { return fallback }
        guard let number = raw.intValue, range.contains(number) else {
            throw ToolError.badArgument(
                name: name,
                reason: "a whole number from \(range.lowerBound) to \(range.upperBound) was expected")
        }
        return number
    }

    /// An object, or an empty one when the argument is left out.
    public func object(_ name: String) throws -> [String: Value] {
        guard let raw = values[name] else { return [:] }
        if case .null = raw { return [:] }
        guard let fields = raw.objectValue else {
            throw ToolError.badArgument(name: name, reason: "an object was expected")
        }
        return fields
    }
}
