import Foundation
import Testing

@testable import EmbeddingAtlasMCPCore

/// The edges of the tool standard for this server: each bound and one past it, the text of
/// each notice, windows that chain, the longest result, and the texts the model reads.
/// Every tool, column and row in here is invented.
@Suite("Bounds")
struct BoundsTests {

    // MARK: Invented views

    /// A view offering `count` tools named `tool_0000`…, each with the given description.
    private static func viewWithTools(count: Int, description: String = "Reads something.") -> FakeView {
        let tools = (0..<count).reversed().map { index in
            #"{"name":"data_get_\#(String(format: "%04d", index))","description":"\#(description)","inputSchema":{"type":"object","properties":{"alpha":{},"beta":{}}}}"#
        }
        return FakeView { request in
            if request.path == "/data/metadata.json" { return FakeView.reply(200, FakeView.metadata) }
            return FakeView.reply(200, #"{"jsonrpc":"2.0","id":1,"result":{"tools":[\#(tools.joined(separator: ","))]}}"#)
        }
    }

    private static func name(_ index: Int) -> String { "data_get_\(String(format: "%04d", index))" }

    private static func viewReturning(text: String) -> FakeView {
        let escaped = String(
            decoding: try! JSONEncoder().encode(text), as: UTF8.self)
        return FakeView.healthy(callResult: #"{"content":[{"type":"text","text":\#(escaped)}]}"#)
    }

    private static func plain(_ count: Int) -> String {
        // Numbered so that a window can be told from another.
        var text = ""
        var index = 0
        while text.count < count {
            text += "row\(index) "
            index += 1
        }
        return String(text.prefix(count))
    }

    private func body(_ output: ToolOutput) -> String {
        output.text.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
    }

    // MARK: atlas_tools: a page of rows

    @Test("The list is one default page, in name order, announced before the data")
    func defaultPage() async {
        let total = ToolCatalog.defaultToolLimit + 5
        let output = await call("atlas_tools", on: Self.viewWithTools(count: total))
        #expect(
            output.text.hasPrefix(
                "Showing 1–\(ToolCatalog.defaultToolLimit) of \(total) tools. Pass offset=\(ToolCatalog.defaultToolLimit) for the next page.\n\n"))
        #expect(output.text.contains(Self.name(0)))
        #expect(output.text.contains(Self.name(ToolCatalog.defaultToolLimit - 1)))
        #expect(!output.text.contains(Self.name(ToolCatalog.defaultToolLimit)))
        #expect(output.text.utf16.count <= ToolStandard.usualPage)
    }

    @Test("The second page starts where the first ended and says that is all")
    func secondPage() async {
        let total = ToolCatalog.defaultToolLimit + 5
        let view = Self.viewWithTools(count: total)
        let output = await call(
            "atlas_tools", ["offset": .int(ToolCatalog.defaultToolLimit)], on: view)
        #expect(
            output.text.hasPrefix(
                "Showing \(ToolCatalog.defaultToolLimit + 1)–\(total) of \(total) tools. That is all.\n\n"))
        #expect(output.text.contains(Self.name(ToolCatalog.defaultToolLimit)))
        #expect(!output.text.contains(Self.name(ToolCatalog.defaultToolLimit - 1)))
        let past = await call("atlas_tools", ["offset": .int(total + 3)], on: view)
        #expect(past.text.hasPrefix("Showing 0 of \(total) tools: offset=\(total + 3) is past the end. That is all."))
    }

    @Test("A list that holds every tool from the start carries no notice")
    func wholeListHasNoNotice() async {
        let output = await call("atlas_tools", on: Self.viewWithTools(count: 3))
        #expect(!output.text.contains("Showing"))
        #expect(!output.text.contains("is outside"))
        #expect(!output.text.contains("clipped"))
    }

    @Test("limit at its maximum is used as asked, one past it is moved and says so")
    func limitEdges() async {
        let maximum = ToolCatalog.toolLimitRange.upperBound
        let view = Self.viewWithTools(count: maximum + 10)
        let at = await call("atlas_tools", ["limit": .int(maximum)], on: view)
        #expect(at.text.hasPrefix("Showing 1–\(maximum) of \(maximum + 10) tools."))
        #expect(!at.text.contains("is outside"))
        let over = await call("atlas_tools", ["limit": .int(maximum + 1)], on: view)
        #expect(over.text.hasPrefix("limit=\(maximum + 1) is outside 1–\(maximum); \(maximum) was used.\n"))
        let under = await call("atlas_tools", ["limit": .int(0)], on: view)
        #expect(under.text.hasPrefix("limit=0 is outside 1–\(maximum); 1 was used.\n"))
    }

    @Test("A full page of the widest rows fits a result without the guard")
    func widestPageFits() async {
        let wide = String(repeating: "word ", count: 200)
        let maximum = ToolCatalog.toolLimitRange.upperBound
        let output = await call(
            "atlas_tools", ["limit": .int(maximum)], on: Self.viewWithTools(count: maximum, description: wide))
        #expect(output.text.utf16.count <= ToolStandard.longestResult)
        #expect(!output.text.contains("Cut at"))
        #expect(output.text.contains(Notice.clipped(field: "Description", width: ToolCatalog.descriptionWidth, tool: "atlas_tools with name")))
    }

    @Test("A description is clipped to its width, and only then is the clip announced")
    func clipping() async {
        let exact = String(repeating: "a", count: ToolCatalog.descriptionWidth)
        let fits = await call("atlas_tools", on: Self.viewWithTools(count: 2, description: exact))
        #expect(!fits.text.contains("clipped"))
        #expect(fits.text.contains(exact))
        let long = exact + "b"
        let clipped = await call("atlas_tools", on: Self.viewWithTools(count: 2, description: long))
        #expect(clipped.text.contains("Description is clipped to \(ToolCatalog.descriptionWidth) characters in each row. Read one in full with atlas_tools with name."))
        #expect(!clipped.text.contains(long))
        let widest = clipped.text.split(separator: "\n").map(\.count).max() ?? 0
        #expect(widest <= 300)
    }

    // MARK: atlas_tools with name: a window

    @Test("One tool is read through windows that chain")
    func oneToolWindows() async {
        let wide = String(repeating: "word ", count: 600)
        let view = Self.viewWithTools(count: 1, description: wide)
        let first = await call(
            "atlas_tools", ["name": .string(Self.name(0)), "max_characters": .int(1000)], on: view)
        #expect(first.text.hasPrefix("Characters 1–1000 of "))
        #expect(first.text.contains("Pass character_offset=1000 for the rest.\n\n"))
        let second = await call(
            "atlas_tools",
            ["name": .string(Self.name(0)), "max_characters": .int(1000), "character_offset": .int(1000)],
            on: view)
        #expect(second.text.hasPrefix("Characters 1001–2000 of "))
        let all = await call(
            "atlas_tools", ["name": .string(Self.name(0)), "max_characters": .int(ToolCatalog.maxCharactersRange.upperBound)],
            on: view)
        #expect(!all.text.hasPrefix("Characters"))
        #expect(all.text.hasPrefix(body(first) + body(second)))
    }

    @Test("An unknown tool name is refused with the call that lists them")
    func unknownName() async {
        let output = await call("atlas_tools", ["name": .string("x")], on: .healthy())
        #expect(output.isError)
        #expect(output.text.contains("call atlas_tools without name"))
    }

    // MARK: atlas_call: plain text in windows

    @Test("Plain text comes in a default window, announced, and the windows chain to the end")
    func plainTextWindows() async {
        let text = Self.plain(ToolCatalog.defaultMaxCharacters * 2 + 500)
        let view = Self.viewReturning(text: text)
        var collected = ""
        var offset = 0
        var first = true
        while offset < text.count {
            let arguments: [String: Value] = ["tool": .string("data_schema"), "character_offset": .int(offset)]
            let output = await call("atlas_call", arguments, on: view)
            #expect(!output.isError)
            let piece = body(output)
            if first {
                #expect(
                    output.text.hasPrefix(
                        "Characters 1–\(ToolCatalog.defaultMaxCharacters) of \(text.count). Pass character_offset=\(ToolCatalog.defaultMaxCharacters) for the rest.\n\n"))
                first = false
            }
            collected += piece
            offset += piece.count
        }
        #expect(collected == text)
        let last = await call(
            "atlas_call", ["tool": .string("data_schema"), "character_offset": .int(ToolCatalog.defaultMaxCharacters * 2)],
            on: view)
        #expect(last.text.hasPrefix("Characters \(ToolCatalog.defaultMaxCharacters * 2 + 1)–\(text.count) of \(text.count). That is all."))
    }

    @Test("A text that fits the window carries no notice")
    func shortTextHasNoNotice() async {
        let output = await call("atlas_call", ["tool": .string("data_schema")], on: Self.viewReturning(text: "plain words"))
        #expect(output.text == "plain words")
    }

    @Test("max_characters at its maximum is used, one past it is moved and says so, a wrong type is refused")
    func maxCharactersEdges() async {
        let maximum = ToolCatalog.maxCharactersRange.upperBound
        let view = Self.viewReturning(text: Self.plain(maximum + 500))
        let at = await call("atlas_call", ["tool": .string("data_schema"), "max_characters": .int(maximum)], on: view)
        #expect(at.text.hasPrefix("Characters 1–\(maximum) of \(maximum + 500)."))
        #expect(at.text.utf16.count <= ToolStandard.longestResult)
        let over = await call("atlas_call", ["tool": .string("data_schema"), "max_characters": .int(maximum + 1)], on: view)
        #expect(over.text.hasPrefix("max_characters=\(maximum + 1) is outside 1–\(maximum); \(maximum) was used.\n"))
        let wrong = await call("atlas_call", ["tool": .string("data_schema"), "max_characters": .string("5")], on: view)
        #expect(wrong.isError)
        #expect(wrong.text.contains("a whole number was expected"))
    }

    @Test("Characters that take two UTF-16 units still fit the longest result, with the notice true")
    func wideCharacters() async {
        let maximum = ToolCatalog.maxCharactersRange.upperBound
        let text = String(repeating: "😀", count: maximum * 2)
        let output = await call(
            "atlas_call", ["tool": .string("data_schema"), "max_characters": .int(maximum)],
            on: Self.viewReturning(text: text))
        #expect(output.text.utf16.count <= ToolStandard.longestResult)
        #expect(!output.text.contains("Cut at"))
        let shown = body(output).count
        #expect(shown < maximum)
        #expect(output.text.contains("Pass character_offset=\(shown) for the rest."))
    }

    @Test("The window arguments are never forwarded, at the top level or nested in arguments")
    func windowArgumentsStayHere() async {
        let view = Self.viewReturning(text: Self.plain(300))
        let top = await call(
            "atlas_call",
            [
                "tool": .string("data_query"), "arguments": .object(["query": .string("SELECT 1")]),
                "max_characters": .int(100),
            ], on: view)
        #expect(top.text.hasPrefix("Characters 1–100 of 300."))
        let nested = await call(
            "atlas_call",
            [
                "tool": .string("data_query"),
                "arguments": .object([
                    "query": .string("SELECT 1"), "max_characters": .int(50), "character_offset": .int(10),
                ]),
            ], on: view)
        #expect(nested.text.hasPrefix("Characters 11–60 of 300."))
        for request in view.requests where request.path == "/mcp" {
            let sent = request.body?.objectValue?["params"]?.objectValue?["arguments"]?.objectValue
            #expect(sent?["max_characters"] == nil)
            #expect(sent?["character_offset"] == nil)
        }
        let topWins = await call(
            "atlas_call",
            [
                "tool": .string("data_query"), "max_characters": .int(20),
                "arguments": .object(["max_characters": .int(50)]),
            ], on: view)
        #expect(topWins.text.hasPrefix("Characters 1–20 of 300."))
    }

    // MARK: Structured text: whole or refused

    @Test("JSON is returned whole, even past the usual page, and never windowed")
    func structuredWhole() async {
        let rows = (0..<1500).map { #"{"n":\#($0)}"# }.joined(separator: ",")
        let json = "[\(rows)]"
        #expect(json.utf16.count > ToolStandard.usualPage)
        let output = await call(
            "atlas_call", ["tool": .string("data_query"), "max_characters": .int(10)],
            on: Self.viewReturning(text: json))
        #expect(output.text.hasSuffix(json))
        #expect(!output.text.contains("Characters 1–"))
    }

    private func json(ofLength length: Int) -> String {
        // `["xxx…"]`: two brackets and two quotes around the filler.
        "[\"" + String(repeating: "x", count: length - 4) + "\"]"
    }

    @Test("JSON at the longest it may be is returned, one more character is refused with its size")
    func structuredEdge() async {
        let limit = ToolCatalog.longestStructuredResult
        let at = await call("atlas_call", ["tool": .string("data_query")], on: Self.viewReturning(text: json(ofLength: limit)))
        #expect(!at.isError)
        #expect(at.text.utf16.count <= ToolStandard.longestResult)
        let over = await call("atlas_call", ["tool": .string("data_query")], on: Self.viewReturning(text: json(ofLength: limit + 1)))
        #expect(over.isError)
        #expect(over.text.contains("of \(limit + 1) characters"))
        #expect(over.text.contains("Narrow the view's own arguments"))
        #expect(over.text.utf16.count < ToolStandard.longestError)
    }

    // MARK: update_atlas

    @Test("update_atlas accepts max_characters, refuses character_offset, and a longer receipt cannot be read again")
    func updateWindow() async {
        let view = Self.viewReturning(text: Self.plain(500))
        let output = await call(
            "update_atlas", ["tool": .string("chart_create"), "max_characters": .int(100)], on: view)
        #expect(output.text.hasPrefix("Cut at 100 of 500 characters; the rest cannot be read again.\n\n"))
        #expect(body(output).count == 100)
        let refused = await call(
            "update_atlas", ["tool": .string("chart_create"), "character_offset": .int(100)], on: view)
        #expect(refused.isError)
        #expect(refused.text.contains("not an argument of this tool"))
        let whole = await call("update_atlas", ["tool": .string("chart_create")], on: view)
        #expect(whole.text == Self.plain(500))
    }

    @Test("A character_offset nested in an update's arguments is refused, not dropped")
    func nestedOffsetRefused() async {
        let output = await call(
            "update_atlas",
            ["tool": .string("chart_create"), "arguments": .object(["character_offset": .int(5)])],
            on: .healthy())
        #expect(output.isError)
        #expect(output.text.contains("no character_offset"))
    }

    @Test("A receipt of JSON too long is refused and says the change was made")
    func updateStructured() async {
        let output = await call(
            "update_atlas", ["tool": .string("chart_create")],
            on: Self.viewReturning(text: json(ofLength: ToolCatalog.longestStructuredResult + 1)))
        #expect(output.isError)
        #expect(output.text.contains("The view ran the tool, so do not repeat the call"))
    }

    @Test("A tab that does not answer an update says the change may still have been made")
    func updateStalled() async {
        let output = await call("update_atlas", ["tool": .string("chart_create")], on: .mcpAnswering(408))
        #expect(output.text.contains("The change may still have been made"))
        let reading = await call("atlas_call", ["tool": .string("data_query")], on: .mcpAnswering(408))
        #expect(!reading.text.contains("may still have been made"))
    }

    // MARK: Arguments

    @Test("An argument the schema does not list is refused with the names allowed, on every tool")
    func unknownArguments() async {
        for tool in ToolCatalog.all() {
            let output = await call(tool.name, ["max_chars": .int(5)], on: .healthy())
            #expect(output.isError, "\(tool.name)")
            #expect(output.text.contains("'max_chars' is not an argument of this tool. Allowed: "))
            for name in ToolCatalog.argumentNames(of: tool) { #expect(output.text.contains(name)) }
        }
        let many = await call("atlas_status", ["a": .int(1), "b": .int(2)], on: .healthy())
        #expect(many.text.contains("'a' (and 1 more)"))
    }

    @Test("A port outside its range is refused, never moved")
    func portIsRefused() async {
        for port in [ToolCatalog.portRange.lowerBound - 1, ToolCatalog.portRange.upperBound + 1] {
            let output = await call("atlas_status", ["port": .int(port)], on: .healthy())
            #expect(output.isError)
        }
        let edge = FakeView.healthy()
        _ = await call("atlas_status", ["port": .int(ToolCatalog.portRange.upperBound)], on: edge)
        #expect(edge.requests.allSatisfy { $0.port == ToolCatalog.portRange.upperBound })
    }

    @Test("An error repeats a caller's text only clipped")
    func errorsClipTheEcho() async {
        let long = String(repeating: "z", count: 500)
        let tool = await call("atlas_call", ["tool": .string(long)], on: .healthy())
        #expect(tool.text.count < 400)
        let unknown = await call(long, on: .healthy())
        #expect(unknown.text.count < 400)
        let name = await call("atlas_tools", ["name": .string(long)], on: .healthy())
        #expect(name.text.count < 400)
    }

    // MARK: Images

    @Test("An image over the limits is reduced inside them and says so before the data")
    func largeImageIsReduced() async throws {
        let png = Pictures.png(width: 3000, height: 1200, noise: true)
        let original = try #require(Data(base64Encoded: png)).count
        #expect(original > ToolCatalog.largestImageBytes)
        let view = FakeView.healthy(
            callResult: #"{"content":[{"type":"image","data":"\#(png)","mimeType":"image/png"}]}"#)
        let output = await call("atlas_call", ["tool": .string("app_screenshot_get")], on: view)
        #expect(!output.isError)
        #expect(output.text.hasPrefix("The image was reduced from 3000×1200 pixels, \(original) bytes, to "))
        guard case .image(let data, let mimeType) = output.content.last else {
            Issue.record("no image")
            return
        }
        let fitted = try #require(Data(base64Encoded: data))
        #expect(fitted.count <= ToolCatalog.largestImageBytes)
        #expect(mimeType == "image/jpeg" || mimeType == "image/png")
        let reread = try #require(ImageBounds.fit(base64: data, mimeType: mimeType))
        #expect(reread.notice == nil)
    }

    @Test("An image wider than the side limit but small in bytes is scaled down")
    func wideImageIsScaled() async throws {
        let png = Pictures.png(width: ToolCatalog.longestImageSide + 1, height: 10)
        let fitted = try #require(ImageBounds.fit(base64: png, mimeType: "image/png"))
        #expect(fitted.notice?.contains("to \(ToolCatalog.longestImageSide)×") == true)
        let within = Pictures.png(width: ToolCatalog.longestImageSide, height: 10)
        #expect(ImageBounds.fit(base64: within, mimeType: "image/png")?.notice == nil)
    }

    @Test("Only the first image is returned, and the others are counted")
    func oneImagePerCall() async {
        let png = Pictures.png(width: 8, height: 8)
        let image = #"{"type":"image","data":"\#(png)","mimeType":"image/png"}"#
        let view = FakeView.healthy(callResult: #"{"content":[\#(image),\#(image),\#(image)]}"#)
        let output = await call("atlas_call", ["tool": .string("app_screenshot_get")], on: view)
        #expect(output.content.filter { if case .image = $0 { true } else { false } }.count == ToolCatalog.maximumImages)
        #expect(output.text.contains("Showing 1 of 3 images; the rest are not returned."))
    }

    @Test("Bytes that are not an image are left out, and the result says so")
    func notAnImage() async {
        let view = FakeView.healthy(
            callResult: #"{"content":[{"type":"image","data":"aGVsbG8=","mimeType":"image/png"}]}"#)
        let output = await call("atlas_call", ["tool": .string("app_screenshot_get")], on: view)
        #expect(output.content.count == 1)
        #expect(output.text.contains("was left out"))
    }

    // MARK: Time

    /// A view that never answers. The deadline abandons the call; nothing waits for it.
    private struct StalledView: ViewConnection {
        func send(port: Int, path: String, body: Data?, timeout: Duration) async throws -> HTTPReply {
            try await Task.sleep(for: .seconds(60))
            return HTTPReply(status: 200, body: Data())
        }
    }

    @Test("A call that outlasts its deadline is abandoned with an error, and an update says the change may have been made")
    func deadline() async {
        let tools = AtlasTools(connection: StalledView(), deadline: .milliseconds(150))
        let reading = await tools.handle(ToolCall(name: "atlas_tools", arguments: [:]))
        #expect(reading.isError)
        #expect(reading.text.contains("Nothing was changed."))
        let update = await tools.handle(ToolCall(name: "update_atlas", arguments: ["tool": .string("chart_create")]))
        #expect(update.text.contains("The change may still have been made"))
    }

    @Test("The timeouts nest: metadata and relay inside the call deadline, inside the standard's limit")
    func timeoutsNest() {
        #expect(AtlasTools.metadataTimeout < AtlasTools.relayTimeout)
        #expect(AtlasTools.relayTimeout + AtlasTools.metadataTimeout < AtlasTools.callDeadline)
        #expect(AtlasTools.callDeadline < ToolStandard.timeLimit)
    }

    // MARK: The texts the model reads

    @Test("The instructions and every tool description are within the longest a client keeps")
    func textsAreWithinTheLimit() {
        #expect(
            ToolStandard.overlongTexts(
                instructions: EmbeddingAtlasMCPServer.instructions, catalog: ToolCatalog.all()
            ).isEmpty)
    }

    @Test("Descriptions and instructions state the bounds the code enforces")
    func descriptionsQuoteTheConstants() {
        let texts = EmbeddingAtlasMCPServer.instructions + ToolCatalog.all().compactMap(\.description).joined()
        for figure in [
            ToolCatalog.defaultToolLimit, ToolCatalog.toolLimitRange.upperBound, ToolCatalog.descriptionWidth,
            ToolCatalog.defaultMaxCharacters, ToolCatalog.maxCharactersRange.upperBound,
            ToolCatalog.longestStructuredResult, ToolCatalog.longestImageSide, ToolCatalog.largestImageBytes,
        ] {
            #expect(texts.contains(String(figure)), "\(figure)")
        }
        #expect(ToolStandard.usualPage == ToolCatalog.defaultMaxCharacters)
    }

    @Test("The schemas state each range and default from the constants")
    func schemasQuoteTheConstants() {
        guard case .object(let schema) = ToolCatalog.call.inputSchema,
            case .object(let properties)? = schema["properties"],
            case .object(let maximum)? = properties["max_characters"]
        else {
            Issue.record("no max_characters")
            return
        }
        #expect(maximum["maximum"] == .int(ToolCatalog.maxCharactersRange.upperBound))
        #expect(maximum["default"] == .int(ToolCatalog.defaultMaxCharacters))
    }

    @Test("The manifest and README quote no figure the code could change")
    func proseHoldsNoFigures() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try String(contentsOf: root.appendingPathComponent("extension/manifest.json"), encoding: .utf8)
        for figure in [ToolCatalog.defaultToolLimit, ToolCatalog.toolLimitRange.upperBound,
                       ToolCatalog.defaultMaxCharacters, ToolCatalog.maxCharactersRange.upperBound,
                       ToolCatalog.longestStructuredResult, ToolCatalog.longestImageSide,
                       ToolCatalog.largestImageBytes] {
            #expect(!manifest.contains(String(figure)))
        }
    }
}
