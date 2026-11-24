import Foundation
import Testing

@testable import EmbeddingAtlasMCPCore

/// Checks on the advertised surface itself. None of these reaches a view.
@Suite("Catalogue")
struct CatalogueTests {

    @Test("Every tool has a unique name, title and description")
    func catalogueIsWellFormed() {
        let tools = ToolCatalog.all()
        let names = tools.map(\.name)
        #expect(names.count == Set(names).count)
        for tool in tools {
            #expect(tool.description?.isEmpty == false, "\(tool.name) has no description")
            #expect(tool.title?.isEmpty == false, "\(tool.name) has no title")
        }
    }

    /// Claude Desktop's schema sanitiser drops a property whose `type` is a union such as
    /// `["string", "null"]` and hands the model a bare `{}` in its place. The fault is
    /// invisible until a caller happens to use that field, so the whole catalogue is
    /// walked here rather than trusted to review.
    @Test("No property declares a union type")
    func noUnionTypesInSchemas() {
        for tool in ToolCatalog.all() {
            guard case .object(let schema) = tool.inputSchema,
                case .object(let properties)? = schema["properties"]
            else { continue }
            for (property, definition) in properties {
                guard case .object(let fields) = definition else { continue }
                if case .array = fields["type"] {
                    Issue.record("\(tool.name).\(property) declares a union type")
                }
            }
        }
    }

    @Test("Reading tools are prefixed atlas_ and annotated read-only; the one that changes carries a verb")
    func namesAndAnnotations() {
        for tool in ToolCatalog.all() where tool.name != ToolCatalog.updateName {
            #expect(tool.name.hasPrefix("atlas_"))
            #expect(tool.annotations.readOnlyHint == true, "\(tool.name) is mis-annotated")
            #expect(tool.annotations.destructiveHint == false, "\(tool.name) is mis-annotated")
        }
        #expect(ToolCatalog.updateName.hasPrefix("update_"))
        #expect(ToolCatalog.update.annotations.readOnlyHint == false)
        #expect(ToolCatalog.update.annotations.destructiveHint == true)
    }

    @Test("No tool reaches beyond this machine")
    func closedWorld() {
        for tool in ToolCatalog.all() {
            #expect(tool.annotations.openWorldHint == false, "\(tool.name) is mis-annotated")
        }
    }

    @Test("Every tool takes a port, and none takes a host or an address")
    func onlyAPort() {
        for tool in ToolCatalog.all() {
            guard case .object(let schema) = tool.inputSchema,
                case .object(let properties)? = schema["properties"]
            else {
                Issue.record("\(tool.name) has no properties")
                continue
            }
            #expect(properties["port"] != nil, "\(tool.name) has no port")
            for forbidden in ["host", "url", "address"] {
                #expect(properties[forbidden] == nil, "\(tool.name) takes a \(forbidden)")
            }
            #expect(schema["additionalProperties"] == .bool(false))
        }
    }

    /// A shipped string never names another server.
    @Test("No text the model reads names another server")
    func noOtherServerNamed() {
        var texts = [EmbeddingAtlasMCPServer.instructions]
        texts += ToolCatalog.all().compactMap(\.description)
        for text in texts {
            #expect(!text.contains("-mcp"))
        }
    }
}
