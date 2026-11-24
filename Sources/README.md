# Sources

- `EmbeddingAtlasMCPCore/`: all the logic, so that the tests can import it. `MCPServer.swift` is the protocol, `ToolCatalog.swift` the four tools, `Dispatch.swift` what each does, `ViewConnection.swift` the only door to a view.
- `embedding-atlas-mcp/`: the launcher. An executable target cannot be imported by a test target, so it holds one line.
