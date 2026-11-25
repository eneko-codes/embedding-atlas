import Foundation

public enum ToolError: Error, Equatable {
    case missingArgument(String)
    case badArgument(name: String, reason: String)
    case viewUnreachable(port: Int)
    case notAView(port: Int, status: Int)
    case viewTimedOut(port: Int)
    case exportedSite
    case noMCPEndpoint
    case noTab
    case tabNotAnswering
    case changesTheView(tool: String)
    case onlyReads(tool: String)
    case viewFailed(String)
    case unknownTool(String)
    case unknownArgument(name: String, others: Int, allowed: [String])
    case tabNotAnsweringDuringChange
    case timedOut(seconds: Int, changing: Bool)
    case structuredTooLong(characters: Int, limit: Int, ran: Bool)

    /// How much of the view's own error text is repeated.
    public static let viewMessageWidth = 500

    public var message: String {
        switch self {
        case .missingArgument(let name):
            return "Missing required argument '\(name)'."

        case .badArgument(let name, let reason):
            return "Argument '\(name)' is not valid: \(reason)"

        case .viewUnreachable(let port):
            return """
                No Embedding Atlas view answers on this Mac at port \(port).

                This server only talks to 127.0.0.1. Either no view is being served, or it is \
                served on another port: pass that port. Starting a view is not something this \
                server can do.
                """

        case .notAView(let port, let status):
            return """
                Something answers at port \(port) on this Mac, but it is not an Embedding Atlas \
                view (HTTP \(status) for its metadata). Check the port.
                """

        case .viewTimedOut(let port):
            return "The view at port \(port) did not answer in time. Nothing was changed."

        case .exportedSite:
            return """
                This is an exported Embedding Atlas site, not a live view: it has no MCP \
                endpoint, so it has no tools to list or call. To read it with these tools, its \
                dataset file has to be served again as a live view with the MCP option.
                """

        case .noMCPEndpoint:
            return """
                This view was started without its MCP option, so it has no tools to list or \
                call. It has to be started again with that option.
                """

        case .noTab:
            return """
                No browser tab has this view open, so its MCP endpoint has nothing to relay to.

                Embedding Atlas runs its tools inside the browser page. Open the view in a \
                browser, keep that tab open and in front, and call again.
                """

        case .tabNotAnswering:
            return """
                A tab has this view open but did not answer in time.

                A tab that is hidden or in the background answers light calls and stalls on \
                queries and screenshots: have that tab brought to the front and call again. Do \
                not open a second tab: the view relays to the last one opened, and the charts \
                are in the first.
                """

        case .changesTheView(let tool):
            return """
                \(ToolStandard.echo(tool)) changes what the view shows, so atlas_call will not run it. Use \
                update_atlas for it.
                """

        case .onlyReads(let tool):
            return "\(ToolStandard.echo(tool)) only reads, so it belongs to atlas_call, not update_atlas."

        case .viewFailed(let reason):
            let clipped = reason.count > Self.viewMessageWidth
                ? String(reason.prefix(Self.viewMessageWidth)) + "…" : reason
            return "The view answered with an error: \(clipped)"

        case .unknownTool(let name):
            return """
                '\(ToolStandard.echo(name))' is not a tool of this server. It has atlas_status, \
                atlas_tools, atlas_call and update_atlas.
                """

        case .unknownArgument(let name, let others, let allowed):
            let more = others > 0 ? " (and \(others) more)" : ""
            return """
                '\(ToolStandard.echo(name))'\(more) is not an argument of this tool. Allowed: \
                \(allowed.joined(separator: ", ")).
                """

        case .tabNotAnsweringDuringChange:
            return ToolError.tabNotAnswering.message + """


                The change may still have been made: read the view's state with atlas_call before \
                repeating it.
                """

        case .timedOut(let seconds, let changing):
            let effect = changing
                ? "The change may still have been made: read the view's state with atlas_call before repeating it."
                : "Nothing was changed."
            return """
                The call did not finish within \(seconds) seconds and was abandoned. \(effect)

                A tab that is hidden or in the background stalls on queries and screenshots: have \
                it brought to the front, and ask for less.
                """

        case .structuredTooLong(let characters, let limit, let ran):
            let effect = ran
                ? "The view ran the tool, so do not repeat the call; only its result is too long to return."
                : "Nothing was changed."
            return """
                The result is structured text (JSON) of \(characters) characters, longer than the \
                \(limit) a result may hold, and it cannot be cut without breaking it. \(effect)

                Narrow the view's own arguments so that it returns less: fewer columns or a LIMIT \
                in a query, one chart or layout instead of all. character_offset and \
                max_characters do not apply to it.
                """
        }
    }
}
