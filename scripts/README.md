# scripts

`pack.sh` builds the release binary for arm64, embeds and checks its `Info.plist`, signs it, and zips `extension/` into `dist/embedding-atlas-mcp.mcpb`. It needs nothing beyond what macOS and Xcode ship.
