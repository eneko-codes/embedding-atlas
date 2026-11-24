import Foundation
import Testing

@testable import EmbeddingAtlasMCPCore

/// Every tool driven end to end against an invented view. No socket, no real view.
@Suite("Tools")
struct ToolsTests {

    // MARK: atlas_status

    @Test("Status reports the address, the column roles, the endpoint and the tab")
    func statusOfAHealthyView() async {
        let output = await call("atlas_status", on: .healthy())
        #expect(!output.isError)
        #expect(output.text.contains("address: http://127.0.0.1:5055"))
        #expect(output.text.contains("view: up"))
        #expect(output.text.contains("projection x=projection_x, y=projection_y"))
        #expect(output.text.contains("neighbours=__neighbors; row id=__row_index__; text=text; image=none"))
        #expect(output.text.contains("kind: live view"))
        #expect(output.text.contains("a browser tab is connected"))
    }

    @Test("Status tells no tab from a tab that does not answer")
    func statusOfTheTab() async {
        #expect(await call("atlas_status", on: .mcpAnswering(503)).text.contains("no browser tab has the view open"))
        #expect(await call("atlas_status", on: .mcpAnswering(408)).text.contains("connected but not answering"))
    }

    @Test("No view at all is an answer to status, not a failure of it")
    func statusWithNoView() async {
        let view = FakeView { _ in throw ConnectionFailure.unreachable }
        let output = await call("atlas_status", on: view)
        #expect(!output.isError)
        #expect(output.text.contains("view: none"))
        #expect(output.text.contains("No Embedding Atlas view answers on this Mac at port 5055"))
    }

    @Test("Status recognises an exported site and a view started without MCP")
    func statusOfOtherKinds() async {
        let site = FakeView { _ in
            FakeView.reply(200, #"{"isStatic":true,"props":{"data":{}},"database":{"type":"wasm"}}"#)
        }
        #expect(await call("atlas_status", on: site).text.contains("kind: exported site"))
        let plain = FakeView { _ in FakeView.reply(200, #"{"props":{"data":{}},"database":{"type":"rest"}}"#) }
        #expect(await call("atlas_status", on: plain).text.contains("mcp endpoint: not enabled"))
    }

    @Test("Something that is not a view is named as such")
    func statusOfAnotherServer() async {
        let other = FakeView { _ in FakeView.reply(404, "not found") }
        #expect(await call("atlas_status", on: other).text.contains("not an Embedding Atlas view"))
    }

    // MARK: port

    @Test("The port argument chooses the port, and only a port")
    func portArgument() async {
        let view = FakeView.healthy()
        _ = await call("atlas_status", ["port": .int(6001)], on: view)
        #expect(view.requests.allSatisfy { $0.port == 6001 })
        let refused = await call("atlas_status", ["port": .int(80)], on: view)
        #expect(refused.isError)
        let text = await call("atlas_status", ["port": .string("6001")], on: view)
        #expect(text.isError)
    }

    // MARK: atlas_tools

    @Test("The list names each tool, its arguments, and whether it changes the view")
    func listsTools() async {
        let output = await call("atlas_tools", on: .healthy())
        #expect(!output.isError)
        #expect(output.text.contains("app_screenshot_get(): Get a full screenshot"))
        #expect(output.text.contains("data_query(query): Run a readonly SQL query"))
        #expect(output.text.contains("chart_create(layoutId, spec) [changes the view]: Create a new chart"))
    }

    @Test("With a name, the list returns that tool's input schema")
    func oneToolsSchema() async {
        let output = await call("atlas_tools", ["name": .string("data_query")], on: .healthy())
        #expect(output.text.contains("data_query (only reads)"))
        #expect(output.text.contains(#"input schema: {"properties":{"query":{"type":"string"}},"type":"object"}"#))
        let missing = await call("atlas_tools", ["name": .string("absent")], on: .healthy())
        #expect(missing.isError)
    }

    @Test("No tab, a stalled tab, no endpoint and an exported site each get their own words")
    func relayFailures() async {
        #expect(await call("atlas_tools", on: .mcpAnswering(503)).text.contains("No browser tab has this view open"))
        #expect(await call("atlas_tools", on: .mcpAnswering(408)).text.contains("did not answer in time"))
        #expect(await call("atlas_tools", on: .mcpAnswering(405)).text.contains("started without its MCP option"))
        let site = FakeView.mcpAnswering(404, metadata: #"{"isStatic":true,"props":{}}"#)
        let output = await call("atlas_tools", on: site)
        #expect(output.isError)
        #expect(output.text.contains("exported Embedding Atlas site"))
    }

    @Test("A connection that times out on the relay is reported as a stalled tab")
    func relayTimeout() async {
        let view = FakeView { request in
            if request.path == "/mcp" { throw ConnectionFailure.timedOut }
            return FakeView.reply(200, FakeView.metadata)
        }
        #expect(await call("atlas_tools", on: view).text.contains("A tab has this view open but did not answer"))
    }

    // MARK: atlas_call

    @Test("A reading tool is relayed with its arguments and its text comes back")
    func callsAReadingTool() async {
        let view = FakeView.healthy()
        let output = await call(
            "atlas_call",
            ["tool": .string("data_query"), "arguments": .object(["query": .string("SELECT count(*) AS n FROM dataset")])],
            on: view)
        #expect(!output.isError)
        #expect(output.text == #"[{"n":400}]"#)
        let sent = view.requests.last?.body?.objectValue
        #expect(sent?["method"]?.stringValue == "tools/call")
        #expect(sent?["params"]?.objectValue?["name"]?.stringValue == "data_query")
        #expect(
            sent?["params"]?.objectValue?["arguments"]?.objectValue?["query"]?.stringValue
                == "SELECT count(*) AS n FROM dataset")
    }

    @Test("A screenshot comes back as an image, unchanged")
    func screenshotsPassThrough() async {
        let view = FakeView.healthy(
            callResult: #"{"content":[{"type":"image","data":"aGVsbG8=","mimeType":"image/png"}]}"#)
        let output = await call("atlas_call", ["tool": .string("app_screenshot_get")], on: view)
        #expect(output.images == [ToolOutput.Image(data: "aGVsbG8=", mimeType: "image/png")])
        #expect(output.text.isEmpty)
        #expect(!output.isError)
    }

    @Test("atlas_call refuses a tool that changes the view, before anything is sent")
    func callRefusesChanges() async {
        let view = FakeView.healthy()
        let output = await call("atlas_call", ["tool": .string("chart_create")], on: view)
        #expect(output.isError)
        #expect(output.text.contains("Use update_atlas"))
        #expect(view.requests.isEmpty)
    }

    @Test("An error object from the view marks the result as an error")
    func viewErrors() async {
        let view = FakeView.healthy(
            callResult: #"{"content":[{"type":"text","text":"{\"error\":\"Only readonly queries are allowed\"}"}]}"#)
        let output = await call("atlas_call", ["tool": .string("data_query")], on: view)
        #expect(output.isError)
        #expect(output.text.contains("Only readonly queries"))
    }

    @Test("Long text is cut at the limit and says so")
    func longTextIsCut() async {
        let long = String(repeating: "x", count: ToolCatalog.maximumTextCharacters + 500)
        let view = FakeView.healthy(callResult: #"{"content":[{"type":"text","text":"\#(long)"}]}"#)
        let output = await call("atlas_call", ["tool": .string("chart_spec_schema")], on: view)
        #expect(output.text.count < long.count)
        #expect(output.text.contains("[cut at \(ToolCatalog.maximumTextCharacters) of \(long.count) characters"))
    }

    @Test("Arguments must be an object and the tool must be named")
    func callArguments() async {
        #expect(await call("atlas_call", on: .healthy()).isError)
        #expect(
            await call("atlas_call", ["tool": .string("data_query"), "arguments": .string("x")], on: .healthy()).isError)
    }

    // MARK: update_atlas

    @Test("update_atlas relays a changing tool and refuses a reading one")
    func updates() async {
        let view = FakeView.healthy(callResult: #"{"content":[{"type":"text","text":"created 7"}]}"#)
        let output = await call(
            "update_atlas", ["tool": .string("chart_create"), "arguments": .object(["layoutId": .string("a")])], on: view)
        #expect(!output.isError)
        #expect(output.text == "created 7")
        let refused = await call("update_atlas", ["tool": .string("data_query")], on: view)
        #expect(refused.isError)
        #expect(refused.text.contains("belongs to atlas_call"))
    }

    // MARK: Policy

    @Test("The view's tools are sorted into readers and changers, and an unknown one is a changer")
    func classification() {
        let reading = [
            "data_schema", "data_query", "app_state_get", "column_style_list", "column_style_get",
            "column_style_schema", "chart_spec_schema", "chart_state_schema", "chart_list", "chart_get_spec",
            "chart_get_state", "layout_spec_schema", "layout_list", "layout_get_current", "layout_get",
            "chart_screenshot_get", "app_screenshot_get", "best_practices",
        ]
        let changing = [
            "column_style_set", "chart_set_spec", "chart_set_state", "chart_clear_state", "chart_create",
            "chart_remove", "layout_set_current", "layout_set", "layout_set_order", "layout_create",
            "layout_remove", "something_new",
        ]
        for name in reading { #expect(!ViewToolPolicy.changesView(name), "\(name)") }
        for name in changing { #expect(ViewToolPolicy.changesView(name), "\(name)") }
    }

    @Test("An unknown tool of this server is an error, and nothing is sent")
    func unknownTool() async {
        let view = FakeView.healthy()
        #expect(await call("atlas_nope", on: view).isError)
        #expect(view.requests.isEmpty)
    }
}
