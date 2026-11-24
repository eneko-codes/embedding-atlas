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
                \(tool) changes what the view shows, so atlas_call will not run it. Use \
                update_atlas for it.
                """

        case .onlyReads(let tool):
            return "\(tool) only reads, so it belongs to atlas_call, not update_atlas."

        case .viewFailed(let reason):
            return "The view answered with an error: \(reason)"
        }
    }
}
