import Foundation

/// Typed access to a `tools/call` argument bag.
///
/// A class, not a struct, so that reading a number can also record that it was moved into
/// its range without every reader having to be `mutating`. One instance serves one call and
/// never leaves it. The tool puts `notices` before the data.
public final class Arguments {
    private let values: [String: Value]

    /// One sentence for each number that was moved into its range, in the order read.
    public private(set) var notices: [String] = []

    public init(_ values: [String: Value]?) {
        self.values = values ?? [:]
    }

    /// `nil` when the argument is absent or null, which mean the same: not given.
    private func given(_ name: String) -> Value? {
        guard let raw = values[name], !raw.isNull else { return nil }
        return raw
    }

    /// Refuses any argument the tool's schema does not list, naming the ones it does. A
    /// call that still uses a name this server dropped must fail, not run without it.
    public func requireOnly(_ allowed: [String]) throws {
        let unknown = values.keys.filter { !allowed.contains($0) }.sorted()
        guard let first = unknown.first else { return }
        throw ToolError.unknownArgument(
            name: first, others: unknown.count - 1, allowed: allowed.sorted())
    }

    /// The same arguments with `defaults` filling the ones that are not given. The notices
    /// read so far carry over.
    func filling(in defaults: [String: Value]) -> Arguments {
        let merged = Arguments(values.merging(defaults) { given, _ in given })
        merged.notices = notices
        return merged
    }

    private func wholeNumber(_ name: String) throws -> Int? {
        guard let raw = given(name) else { return nil }
        guard let number = raw.intValue else {
            throw ToolError.badArgument(name: name, reason: "a whole number was expected")
        }
        return number
    }

    public func optionalString(_ name: String) throws -> String? {
        guard let raw = given(name) else { return nil }
        guard let text = raw.stringValue else {
            throw ToolError.badArgument(name: name, reason: "text was expected")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func requiredString(_ name: String) throws -> String {
        guard let text = try optionalString(name) else { throw ToolError.missingArgument(name) }
        return text
    }

    /// A quantity: a size, a count, a position. Outside its range it is moved to the
    /// nearest allowed value, and `notices` gains the sentence that says which was used.
    public func int(_ name: String, default fallback: Int, in range: ClosedRange<Int>) throws
        -> Int
    {
        guard let number = try wholeNumber(name) else { return fallback }
        return ToolStandard.clamp(number, to: range, argument: name, notices: &notices)
    }

    /// An identifier: a port. Outside its range it is refused, not moved, because the
    /// nearest allowed value would name another view than the one asked for.
    public func identifier(_ name: String, default fallback: Int, in range: ClosedRange<Int>) throws
        -> Int
    {
        guard let number = try wholeNumber(name) else { return fallback }
        guard range.contains(number) else {
            throw ToolError.badArgument(
                name: name,
                reason: "a whole number from \(range.lowerBound) to \(range.upperBound) was expected")
        }
        return number
    }

    /// The `limit` and `offset` of a listing.
    public func page(defaultLimit: Int, limits: ClosedRange<Int>) throws -> (limit: Int, offset: Int) {
        (
            try int("limit", default: defaultLimit, in: limits),
            try int("offset", default: 0, in: ToolCatalog.offsetRange)
        )
    }

    /// The `character_offset` and `max_characters` of a window on a long text.
    public func window(offsetAllowed: Bool = true) throws -> (characterOffset: Int, maxCharacters: Int) {
        (
            offsetAllowed ? try int("character_offset", default: 0, in: ToolCatalog.offsetRange) : 0,
            try int(
                "max_characters", default: ToolCatalog.defaultMaxCharacters,
                in: ToolCatalog.maxCharactersRange)
        )
    }

    /// An object, or an empty one when the argument is left out.
    public func object(_ name: String) throws -> [String: Value] {
        guard let raw = given(name) else { return [:] }
        guard let fields = raw.objectValue else {
            throw ToolError.badArgument(name: name, reason: "an object was expected")
        }
        return fields
    }
}
