import Foundation

/// Routes a `tools/call` to the view and renders the answer.
///
/// Never opens a connection itself: everything goes through `ViewConnection`, which is
/// what lets the tests drive every branch below against an in-memory double.
public struct AtlasTools: Sendable {
    private let connection: any ViewConnection

    /// The view gives up on its browser tab after half a minute. Waiting a little longer
    /// than that means the answer about a stalled tab is the view's, not a bare timeout.
    public static let relayTimeout = Duration.seconds(45)
    public static let metadataTimeout = Duration.seconds(10)

    public init(connection: any ViewConnection) {
        self.connection = connection
    }

    public func handle(_ call: ToolCall) async -> ToolOutput {
        let start = ContinuousClock.now
        do {
            let arguments = Arguments(call.arguments)
            let port = try arguments.int(
                "port", default: ToolCatalog.defaultPort, in: ToolCatalog.portRange)
            switch call.name {
            case ToolCatalog.statusName: return try await status(port: port)
            case ToolCatalog.toolsName: return try await tools(arguments, port: port)
            case ToolCatalog.callName: return try await forward(arguments, port: port, changing: false)
            case ToolCatalog.updateName: return try await forward(arguments, port: port, changing: true)
            default: return ToolOutput(text: "Unknown tool.", isError: true)
            }
        } catch let error as ToolError {
            Diagnostics.toolFailed(call.name, error: error, since: start)
            return ToolOutput(text: error.message, isError: true)
        } catch {
            Diagnostics.toolFailed(call.name, error: error, since: start)
            return ToolOutput(text: "The call failed inside this server.", isError: true)
        }
    }

    // MARK: The view

    private func send(port: Int, path: String, body: Value?, timeout: Duration) async throws -> HTTPReply {
        do {
            return try await connection.send(
                port: port, path: path, body: body.flatMap { try? JSONEncoder().encode($0) },
                timeout: timeout)
        } catch ConnectionFailure.timedOut {
            throw ToolError.viewTimedOut(port: port)
        } catch {
            throw ToolError.viewUnreachable(port: port)
        }
    }

    func metadata(port: Int) async throws -> [String: Value] {
        let reply = try await send(
            port: port, path: "/data/metadata.json", body: nil, timeout: Self.metadataTimeout)
        guard reply.status == 200,
            let fields = (try? JSONDecoder().decode(Value.self, from: reply.body))?.objectValue
        else {
            throw ToolError.notAView(port: port, status: reply.status)
        }
        return fields
    }

    /// One JSON-RPC call to the view's own MCP endpoint, returning its `result`.
    func relay(port: Int, method: String, parameters: Value? = nil) async throws -> [String: Value] {
        var message: [String: Value] = [
            "jsonrpc": .string("2.0"), "id": .int(1), "method": .string(method),
        ]
        if let parameters { message["params"] = parameters }
        let reply: HTTPReply
        do {
            reply = try await send(
                port: port, path: "/mcp", body: .object(message), timeout: Self.relayTimeout)
        } catch ToolError.viewTimedOut {
            throw ToolError.tabNotAnswering
        }
        switch reply.status {
        case 200:
            guard let fields = (try? JSONDecoder().decode(Value.self, from: reply.body))?.objectValue
            else { throw ToolError.viewFailed("its answer was not JSON") }
            if let failure = fields["error"]?.objectValue {
                throw ToolError.viewFailed(failure["message"]?.stringValue ?? "no message")
            }
            return fields["result"]?.objectValue ?? [:]
        case 503: throw ToolError.noTab
        case 408: throw ToolError.tabNotAnswering
        case 404, 405:
            // A site exported from a view answers its metadata and has no endpoint at all.
            if (try? await metadata(port: port))?["isStatic"]?.boolValue == true {
                throw ToolError.exportedSite
            }
            throw ToolError.noMCPEndpoint
        default: throw ToolError.viewFailed("HTTP \(reply.status)")
        }
    }

    // MARK: atlas_status

    func status(port: Int) async throws -> ToolOutput {
        var lines = ["address: http://127.0.0.1:\(port)"]
        let metadata: [String: Value]
        do {
            metadata = try await self.metadata(port: port)
        } catch let error as ToolError {
            // Nothing to read is an answer to this tool, not a failure of it.
            lines.append("view: none\n\n\(error.message)")
            return ToolOutput(text: lines.joined(separator: "\n"), isError: false)
        }
        lines.append("view: up")
        let data = metadata["props"]?.objectValue?["data"]?.objectValue
        let projection = data?["projection"]?.objectValue
        func column(_ fields: [String: Value]?, _ key: String) -> String {
            fields?[key]?.stringValue ?? "none"
        }
        lines.append(
            "columns: projection x=\(column(projection, "x")), y=\(column(projection, "y")); "
                + "neighbours=\(column(data, "neighbors")); row id=\(column(data, "id")); "
                + "text=\(column(data, "text")); image=\(column(data, "image"))")
        if metadata["isStatic"]?.boolValue == true {
            lines.append("kind: exported site, with no MCP endpoint")
            return ToolOutput(text: lines.joined(separator: "\n"), isError: false)
        }
        lines.append("kind: live view")
        guard metadata["mcp"] != nil else {
            lines.append("mcp endpoint: not enabled; the view was started without its MCP option")
            return ToolOutput(text: lines.joined(separator: "\n"), isError: false)
        }
        do {
            _ = try await relay(port: port, method: "tools/list")
            lines.append("mcp endpoint: enabled, a browser tab is connected")
        } catch ToolError.noTab {
            lines.append("mcp endpoint: enabled, no browser tab has the view open")
        } catch ToolError.tabNotAnswering {
            lines.append(
                "mcp endpoint: enabled, a tab is connected but not answering (hidden or in the background?)")
        }
        return ToolOutput(text: lines.joined(separator: "\n"), isError: false)
    }

    // MARK: atlas_tools

    func tools(_ arguments: Arguments, port: Int) async throws -> ToolOutput {
        let listed = try await relay(port: port, method: "tools/list")["tools"]?.arrayValue ?? []
        if let wanted = arguments.optionalString("name") {
            guard let tool = listed.first(where: { $0.objectValue?["name"]?.stringValue == wanted })?
                .objectValue
            else {
                throw ToolError.badArgument(name: "name", reason: "the view has no tool named \(wanted)")
            }
            let schema = tool["inputSchema"].flatMap(Self.compact) ?? "{}"
            let kind = ViewToolPolicy.changesView(wanted) ? "changes the view" : "only reads"
            let text =
                "\(wanted) (\(kind)): \(tool["description"]?.stringValue ?? "")\ninput schema: \(schema)"
            return ToolOutput(text: Self.cut(text), isError: false)
        }
        let lines = listed.compactMap { entry -> String? in
            guard let tool = entry.objectValue, let name = tool["name"]?.stringValue else { return nil }
            let names = (tool["inputSchema"]?.objectValue?["properties"]?.objectValue ?? [:]).keys.sorted()
            let description = (tool["description"]?.stringValue ?? "")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let mark = ViewToolPolicy.changesView(name) ? " [changes the view]" : ""
            return "\(name)(\(names.joined(separator: ", ")))\(mark): \(description)"
        }
        return ToolOutput(text: Self.cut(lines.joined(separator: "\n")), isError: false)
    }

    // MARK: atlas_call and update_atlas

    func forward(_ arguments: Arguments, port: Int, changing: Bool) async throws -> ToolOutput {
        let tool = try arguments.requiredString("tool")
        let toolArguments = try arguments.object("arguments")
        if ViewToolPolicy.changesView(tool) != changing {
            throw changing ? ToolError.onlyReads(tool: tool) : ToolError.changesTheView(tool: tool)
        }
        let result = try await relay(
            port: port, method: "tools/call",
            parameters: .object(["name": .string(tool), "arguments": .object(toolArguments)]))

        var failed = result["isError"]?.boolValue ?? false
        var texts: [String] = []
        var images: [ToolOutput.Image] = []
        for item in result["content"]?.arrayValue ?? [] {
            guard let block = item.objectValue else { continue }
            switch block["type"]?.stringValue {
            case "text":
                let text = block["text"]?.stringValue ?? ""
                // A failure inside the view comes back as a JSON object with "error".
                if text.trimmingCharacters(in: .whitespaces).hasPrefix("{\"error\"") { failed = true }
                texts.append(text)
            case "image":
                if let data = block["data"]?.stringValue, let mimeType = block["mimeType"]?.stringValue {
                    images.append(ToolOutput.Image(data: data, mimeType: mimeType))
                }
            default:
                texts.append("[content of a kind this server does not relay]")
            }
        }
        var text = Self.cut(texts.joined(separator: "\n"))
        if text.isEmpty && images.isEmpty { text = "(the view returned no content)" }
        return ToolOutput(text: text, images: images, isError: failed)
    }

    // MARK: Shared

    static func compact(_ value: Value) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }

    static func cut(_ text: String) -> String {
        let limit = ToolCatalog.maximumTextCharacters
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
            + "\n[cut at \(limit) of \(text.count) characters: ask for less]"
    }
}
