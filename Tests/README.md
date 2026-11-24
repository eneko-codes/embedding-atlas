# Tests

Every test runs against `FakeView`, an invented view held in memory. Nothing here opens a socket or reaches a real view.

- `ProtocolTests`: the MCP wire protocol, JSON text in and out.
- `ToolsTests`: each tool end to end.
- `CatalogueTests`: the advertised tools and their schemas.
- `VersionTests`: the manifest, the server constant and `Info.plist` agree.
