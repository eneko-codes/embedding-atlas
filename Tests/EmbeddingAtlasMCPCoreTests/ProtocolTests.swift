import Foundation
import Testing

@testable import EmbeddingAtlasMCPCore

/// The MCP wire protocol, driven as JSON text in and JSON text out against an invented
/// view. Nothing here touches stdin, stdout or a real view.
@Suite("Protocol")
struct ProtocolTests {

    private func handler(view: FakeView = .healthy()) -> MCPHandler {
        EmbeddingAtlasMCPServer.handler(tools: AtlasTools(connection: view))
    }

    private func decode(_ line: String?) throws -> [String: Value] {
        let text = try #require(line)
        let value = try JSONDecoder().decode(Value.self, from: Data(text.utf8))
        return try #require(value.objectValue)
    }

    private func result(_ line: String?) throws -> [String: Value] {
        try #require(try decode(line)["result"]?.objectValue)
    }

    private func errorCode(_ line: String?) throws -> Int? {
        try decode(line)["error"]?.objectValue?["code"]?.intValue
    }

    @Test("initialize echoes a protocol version the server supports")
    func initializeEchoesSupportedVersion() async throws {
        for version in ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"] {
            let reply = await handler().respond(
                to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(version)","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}"#)
            #expect(try result(reply)["protocolVersion"]?.stringValue == version)
        }
    }

    @Test("initialize answers with the newest version when the client asks for an unknown one")
    func initializeFallsBackToNewest() async throws {
        let reply = await handler().respond(
            to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        #expect(try result(reply)["protocolVersion"]?.stringValue == "2025-11-25")
    }

    @Test("initialize names the server, its tools capability and its instructions")
    func initializeDescribesServer() async throws {
        let reply = await handler().respond(
            to: #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        let body = try result(reply)
        #expect(body["serverInfo"]?.objectValue?["name"]?.stringValue == EmbeddingAtlasMCPServer.name)
        #expect(body["serverInfo"]?.objectValue?["version"]?.stringValue == EmbeddingAtlasMCPServer.version)
        #expect(body["instructions"]?.stringValue == EmbeddingAtlasMCPServer.instructions)
        #expect(body["capabilities"]?.objectValue?["tools"]?.objectValue?["listChanged"]?.boolValue == false)
    }

    @Test("A request keeps its id, whether a number or a string")
    func idsAreEchoed() async throws {
        let number = await handler().respond(to: #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)
        #expect(try decode(number)["id"] == .int(7))
        let text = await handler().respond(to: #"{"jsonrpc":"2.0","id":"a-1","method":"ping"}"#)
        #expect(try decode(text)["id"] == .string("a-1"))
    }

    @Test("tools/list offers exactly the catalogue")
    func toolsList() async throws {
        let reply = await handler().respond(to: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let names = try result(reply)["tools"]?.arrayValue?.compactMap { $0.objectValue?["name"]?.stringValue }
        #expect(names == ["atlas_status", "atlas_tools", "atlas_call", "update_atlas"])
    }

    @Test("tools/call returns text content and the error flag")
    func toolsCall() async throws {
        let reply = await handler().respond(
            to: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"atlas_status"}}"#)
        let body = try result(reply)
        #expect(body["isError"]?.boolValue == false)
        let block = try #require(body["content"]?.arrayValue?.first?.objectValue)
        #expect(block["type"]?.stringValue == "text")
        #expect(block["text"]?.stringValue?.contains("view: up") == true)
    }

    @Test("A screenshot is returned as an image content block")
    func imageContent() async throws {
        let png = Pictures.png(width: 16, height: 16)
        let view = FakeView.healthy(
            callResult: #"{"content":[{"type":"image","data":"\#(png)","mimeType":"image/png"}]}"#)
        let reply = await handler(view: view).respond(
            to: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"atlas_call","arguments":{"tool":"app_screenshot_get"}}}"#)
        let blocks = try #require(try result(reply)["content"]?.arrayValue)
        #expect(blocks.count == 1)
        #expect(blocks[0].objectValue?["type"]?.stringValue == "image")
        #expect(blocks[0].objectValue?["data"]?.stringValue == png)
        #expect(blocks[0].objectValue?["mimeType"]?.stringValue == "image/png")
    }

    @Test("A notification is never answered, known or not")
    func notificationsAreSilent() async {
        #expect(await handler().respond(to: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(await handler().respond(to: #"{"jsonrpc":"2.0","method":"notifications/unknown"}"#) == nil)
    }

    @Test("Bad input gets the JSON-RPC error that names it")
    func errors() async throws {
        #expect(try errorCode(await handler().respond(to: "not json")) == -32700)
        #expect(try errorCode(await handler().respond(to: "[1,2]")) == -32600)
        #expect(try errorCode(await handler().respond(to: #"{"jsonrpc":"2.0","id":1,"method":"resources/list"}"#)) == -32601)
        #expect(try errorCode(await handler().respond(to: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}"#)) == -32602)
    }

    @Test("Every reply is exactly one line")
    func repliesAreOneLine() async throws {
        let reply = await handler().respond(to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        #expect(try #require(reply).contains("\n") == false)
    }
}
