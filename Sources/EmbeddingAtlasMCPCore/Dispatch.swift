import Foundation

/// Routes a `tools/call` to the view and renders the answer.
///
/// Never opens a connection itself: everything goes through `ViewConnection`, which is
/// what lets the tests drive every branch below against an in-memory double.
public struct AtlasTools: ToolHandler {
    private let connection: any ViewConnection

    /// The view gives up on its browser tab after half a minute. Waiting a little longer
    /// than that means the answer about a stalled tab is the view's, not a bare timeout.
    public static let relayTimeout = Duration.seconds(45)
    public static let metadataTimeout = Duration.seconds(10)

    /// The longest a whole call may take: a metadata request and a relay one, with room.
    /// It sits above both, because the connection's own timeout is a wait for silence and
    /// not a limit on the whole answer, and inside `ToolStandard.timeLimit`.
    public static let callDeadline = Duration.seconds(90)

    private let deadline: Duration

    public init(connection: any ViewConnection, deadline: Duration = AtlasTools.callDeadline) {
        self.connection = connection
        self.deadline = deadline
    }

    public func handle(_ call: ToolCall) async -> ToolOutput {
        let start = ContinuousClock.now
        let outcome = await Deadline.run(within: deadline) { await self.run(call, since: start) }
        if let outcome { return outcome }
        let error = ToolError.timedOut(
            seconds: Int(deadline.components.seconds), changing: call.name == ToolCatalog.updateName)
        Diagnostics.toolFailed(call.name, error: error, since: start)
        return ToolOutput(text: error.message, isError: true)
    }

    private func run(_ call: ToolCall, since start: ContinuousClock.Instant) async -> ToolOutput {
        do {
            guard let tool = ToolCatalog.all().first(where: { $0.name == call.name }) else {
                throw ToolError.unknownTool(call.name)
            }
            let arguments = Arguments(call.arguments)
            try arguments.requireOnly(ToolCatalog.argumentNames(of: tool))
            let port = try arguments.identifier(
                "port", default: ToolCatalog.defaultPort, in: ToolCatalog.portRange)
            switch call.name {
            case ToolCatalog.statusName: return try await status(port: port)
            case ToolCatalog.toolsName: return try await tools(arguments, port: port)
            case ToolCatalog.callName: return try await forward(arguments, port: port, changing: false)
            default: return try await forward(arguments, port: port, changing: true)
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

    private struct ToolRow {
        var name: String
        var line: String
        var clipped: Bool
    }

    func tools(_ arguments: Arguments, port: Int) async throws -> ToolOutput {
        let listed = try await relay(port: port, method: "tools/list")["tools"]?.arrayValue ?? []
        if let wanted = try arguments.optionalString("name") {
            let window = try arguments.window()
            guard let tool = listed.first(where: { $0.objectValue?["name"]?.stringValue == wanted })?
                .objectValue
            else {
                throw ToolError.badArgument(
                    name: "name",
                    reason: "the view has no tool named \(ToolStandard.echo(wanted)); call atlas_tools without name to list them")
            }
            let schema = tool["inputSchema"].flatMap(Self.compact) ?? "{}"
            let kind = ViewToolPolicy.changesView(wanted) ? "changes the view" : "only reads"
            let text =
                "\(wanted) (\(kind)): \(tool["description"]?.stringValue ?? "")\ninput schema: \(schema)"
            let notices = arguments.notices
            return ToolOutput(
                text: ToolStandard.fitting(window.maxCharacters) { size in
                    let part = ToolStandard.window(
                        of: text, characterOffset: window.characterOffset, maxCharacters: size)
                    return ToolStandard.withNotices(notices + [part.notice].compactMap { $0 }, part.text)
                }, isError: false)
        }

        let (limit, offset) = try arguments.page(
            defaultLimit: ToolCatalog.defaultToolLimit, limits: ToolCatalog.toolLimitRange)
        // By name, and by position in the view's list when two share one, so no two rows tie.
        let rows = listed.enumerated().compactMap { index, entry -> (Int, ToolRow)? in
            guard let tool = entry.objectValue, let name = tool["name"]?.stringValue else { return nil }
            let names = (tool["inputSchema"]?.objectValue?["properties"]?.objectValue ?? [:]).keys.sorted()
            let description = (tool["description"]?.stringValue ?? "")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let width = ToolCatalog.descriptionWidth
            let clipped = description.count > width
            let shown = clipped ? String(description.prefix(width - 1)) + "…" : description
            let mark = ViewToolPolicy.changesView(name) ? " [changes the view]" : ""
            return (
                index,
                ToolRow(
                    name: name, line: "\(name)(\(names.joined(separator: ", ")))\(mark): \(shown)",
                    clipped: clipped)
            )
        }.sorted { ($0.1.name, $0.0) < ($1.1.name, $1.0) }.map(\.1)

        guard !rows.isEmpty else {
            return ToolOutput(
                text: ToolStandard.withNotices(arguments.notices, "The view offers no tools."),
                isError: false)
        }
        let notices = arguments.notices
        return ToolOutput(
            text: ToolStandard.fitting(limit) { size in
                let page = Array(rows.dropFirst(offset).prefix(size))
                var all = notices
                if let position = Notice.page(
                    offset: offset, count: page.count, total: rows.count, things: "tools")
                {
                    all.append(position)
                }
                if page.contains(where: \.clipped) {
                    all.append(
                        Notice.clipped(
                            field: "Description", width: ToolCatalog.descriptionWidth,
                            tool: "atlas_tools with name"))
                }
                return ToolStandard.withNotices(all, page.map(\.line).joined(separator: "\n"))
            }, isError: false)
    }

    // MARK: atlas_call and update_atlas

    /// What the view's tool returned: its text blocks, its images, whether it failed.
    private struct ViewResult {
        var failed = false
        var blocks: [String] = []
        var images: [(data: String, mimeType: String)] = []
    }

    func forward(_ arguments: Arguments, port: Int, changing: Bool) async throws -> ToolOutput {
        let tool = try arguments.requiredString("tool")
        var forwarded = try arguments.object("arguments")
        if ViewToolPolicy.changesView(tool) != changing {
            throw changing ? ToolError.onlyReads(tool: tool) : ToolError.changesTheView(tool: tool)
        }
        // The window arguments are this server's own. A caller that nests them with the
        // view's arguments still gets the window it asked for, and the view never sees them.
        if changing, forwarded["character_offset"] != nil {
            throw ToolError.badArgument(
                name: "arguments.character_offset",
                reason: "update_atlas has no character_offset, because asking again would repeat the change")
        }
        var nested: [String: Value] = [:]
        for name in ["character_offset", "max_characters"] {
            if let value = forwarded.removeValue(forKey: name) { nested[name] = value }
        }
        let reading = arguments.filling(in: nested)
        let window = try reading.window(offsetAllowed: !changing)

        let result: [String: Value]
        do {
            result = try await relay(
                port: port, method: "tools/call",
                parameters: .object(["name": .string(tool), "arguments": .object(forwarded)]))
        } catch ToolError.tabNotAnswering where changing {
            throw ToolError.tabNotAnsweringDuringChange
        }

        var viewResult = ViewResult(failed: result["isError"]?.boolValue ?? false)
        for item in result["content"]?.arrayValue ?? [] {
            guard let block = item.objectValue else { continue }
            switch block["type"]?.stringValue {
            case "text":
                let text = block["text"]?.stringValue ?? ""
                // A failure inside the view comes back as a JSON object with "error".
                if text.trimmingCharacters(in: .whitespaces).hasPrefix("{\"error\"") {
                    viewResult.failed = true
                }
                viewResult.blocks.append(text)
            case "image":
                if let data = block["data"]?.stringValue, let mimeType = block["mimeType"]?.stringValue {
                    viewResult.images.append((data, mimeType))
                }
            default:
                viewResult.blocks.append("[content of a kind this server does not relay]")
            }
        }
        return try shaped(
            viewResult, window: window, notices: reading.notices, changing: changing)
    }

    /// One result inside the standard: images fitted, text windowed or refused, and every
    /// notice before the data.
    private func shaped(
        _ result: ViewResult, window: (characterOffset: Int, maxCharacters: Int),
        notices: [String], changing: Bool
    ) throws -> ToolOutput {
        var notices = notices
        var images: [ToolOutput.Block] = []
        for (index, image) in result.images.enumerated() {
            if index >= ToolCatalog.maximumImages { continue }
            guard let fitted = ImageBounds.fit(base64: image.data, mimeType: image.mimeType) else {
                notices.append(
                    "The image the view returned could not be read or brought within \(ToolCatalog.longestImageSide) pixels and \(ToolCatalog.largestImageBytes) bytes, and was left out.")
                continue
            }
            if let notice = fitted.notice { notices.append(notice) }
            images.append(.image(data: fitted.data, mimeType: fitted.mimeType))
        }
        if result.images.count > ToolCatalog.maximumImages {
            notices.append(
                "Showing \(ToolCatalog.maximumImages) of \(result.images.count) images; the rest are not returned.")
        }

        let whole = result.blocks.joined(separator: "\n")
        var text: String
        if whole.isEmpty {
            text = images.isEmpty && notices.isEmpty ? "(the view returned no content)" : ""
            text = ToolStandard.withNotices(notices, text)
        } else if Self.isStructured(result.blocks) {
            let size = whole.utf16.count + notices.joined(separator: "\n").utf16.count
            guard size <= ToolCatalog.longestStructuredResult else {
                throw ToolError.structuredTooLong(
                    characters: size, limit: ToolCatalog.longestStructuredResult,
                    ran: changing && !result.failed)
            }
            text = ToolStandard.withNotices(notices, whole)
        } else {
            let total = whole.count
            let fixed = notices
            text = ToolStandard.fitting(window.maxCharacters) { size in
                if changing {
                    // Asking again would repeat the change, so nothing here is resumable.
                    let shown = String(whole.prefix(size))
                    let cut = total > size
                        ? ["Cut at \(size) of \(total) characters; the rest cannot be read again."] : []
                    return ToolStandard.withNotices(fixed + cut, shown)
                }
                let part = ToolStandard.window(
                    of: whole, characterOffset: window.characterOffset, maxCharacters: size)
                return ToolStandard.withNotices(fixed + [part.notice].compactMap { $0 }, part.text)
            }
        }
        // Text first, so that a note about a picture is read before the picture.
        return ToolOutput(
            content: (text.isEmpty ? [] : [.text(text)]) + images, isError: result.failed)
    }

    /// Structured when every text block is a JSON object or array: cutting it mid-way would
    /// break it, so it is returned whole or refused.
    static func isStructured(_ blocks: [String]) -> Bool {
        let filled = blocks.filter { !$0.allSatisfy(\.isWhitespace) }
        guard !filled.isEmpty else { return false }
        return filled.allSatisfy { block in
            guard let first = block.first(where: { !$0.isWhitespace }), first == "{" || first == "[" else {
                return false
            }
            return (try? JSONSerialization.jsonObject(with: Data(block.utf8))) != nil
        }
    }

    // MARK: Shared

    static func compact(_ value: Value) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }
}
