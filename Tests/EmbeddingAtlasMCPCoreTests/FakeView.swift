import Foundation
import Synchronization

@testable import EmbeddingAtlasMCPCore

/// An invented view held in memory: it answers by path and records what it was sent.
/// Nothing here opens a socket.
final class FakeView: ViewConnection, Sendable {

    struct Request: Sendable, Equatable {
        var port: Int
        var path: String
        var body: Value?
    }

    private let recorded = Mutex<[Request]>([])
    private let answer: @Sendable (Request) throws -> HTTPReply

    init(_ answer: @escaping @Sendable (Request) throws -> HTTPReply) {
        self.answer = answer
    }

    var requests: [Request] { recorded.withLock { $0 } }

    func send(port: Int, path: String, body: Data?, timeout: Duration) async throws -> HTTPReply {
        let request = Request(
            port: port, path: path,
            body: body.flatMap { try? JSONDecoder().decode(Value.self, from: $0) })
        recorded.withLock { $0.append(request) }
        return try answer(request)
    }

    static func reply(_ status: Int, _ json: String) -> HTTPReply {
        HTTPReply(status: status, body: Data(json.utf8))
    }

    static let metadata = """
        {"props":{"data":{"id":"__row_index__","projection":{"x":"projection_x","y":"projection_y"},\
        "text":"text","neighbors":"__neighbors"}},"database":{"type":"rest"},"mcp":{"type":"websocket"}}
        """

    static let toolList = """
        {"tools":[\
        {"name":"app_screenshot_get","description":"Get a full  screenshot","inputSchema":{"type":"object"}},\
        {"name":"data_query","description":"Run a readonly SQL query","inputSchema":{"type":"object","properties":{"query":{"type":"string"}}}},\
        {"name":"chart_create","description":"Create a new chart","inputSchema":{"type":"object","properties":{"layoutId":{},"spec":{}}}}\
        ]}
        """

    /// A live view with its MCP endpoint and a connected tab. `callResult` is the JSON of
    /// the `result` it gives to any `tools/call`.
    static func healthy(
        callResult: String = #"{"content":[{"type":"text","text":"[{\"n\":400}]"}]}"#
    ) -> FakeView {
        FakeView { request in
            switch request.path {
            case "/data/metadata.json":
                return reply(200, metadata)
            case "/mcp":
                let method = request.body?.objectValue?["method"]?.stringValue
                let result = method == "tools/list" ? toolList : callResult
                return reply(200, #"{"jsonrpc":"2.0","id":1,"result":\#(result)}"#)
            default:
                return reply(404, "{}")
            }
        }
    }

    /// A view whose MCP endpoint answers every call with one HTTP status.
    static func mcpAnswering(_ status: Int, metadata: String = FakeView.metadata) -> FakeView {
        FakeView { request in
            request.path == "/mcp" ? reply(status, #"{"detail":"x"}"#) : reply(200, metadata)
        }
    }
}

func call(_ name: String, _ arguments: [String: Value] = [:], on view: FakeView) async -> ToolOutput {
    await AtlasTools(connection: view).handle(ToolCall(name: name, arguments: arguments))
}
