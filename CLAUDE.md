# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Data rule

A view holds somebody's dataset. Everything this server relays is that data: rows, column names, chart specs, a picture of the screen.

**Tests run against fakes** — `FakeView`, an in-memory view with invented answers. Never a real view, and never out of convenience: the suite exists to catch breaking changes and does not need real data to do that.

**Trying the server against a live view is legitimate, but it is the owner's call, not yours.** Ask in chat as an explicit choice they can pick, saying which view, which tools you will call and what they return. A view of invented data that you started yourself for the purpose needs no question. A yes covers that run only.

`update_atlas` changes what a view shows, in a browser tab that may be the owner's own screen. Never call it on a view you did not start.

## What this is

Two parts:

- A local MCP server (Swift 6, stdio transport) packaged as a Claude Desktop extension. It reaches the MCP server Embedding Atlas provides for a running view and passes that view's tools through. HTTP to `127.0.0.1` only, no file access, no user configuration, **no third-party dependency**: `Package.swift` lists none, and the MCP protocol (JSON-RPC over stdio) is `MCPServer.swift` over Foundation. Adding a package needs the owner's say-so. **`MCPServer.swift`, `Value.swift`, `ToolStandard.swift` and the tests `MCPProtocolTests.swift` and `ToolStandardTests.swift` are copied unchanged into every one of the owner's MCP servers** (the test files differ only in their `@testable import`). A change to one is made to every copy in the same piece of work; never let a copy drift.

- `plugin/`: three skills about using Embedding Atlas. They say nothing about where the tool runs, and they register no MCP server.

`ToolStandard.swift` holds what every tool here must keep to: the longest result, description and error, the time a call may take, the fixed wording of each notice that says what a result left out (`Notice`), and the guard `MCPServer.swift` passes every result through. A tool bounds its own result and says how to get the rest; the guard only catches the one that forgot. `Deadline`, which abandons a call at its time limit, is part of `ToolStandard.swift`.

## Facts easy to get wrong

- **Embedding Atlas answers MCP calls from the browser page.** `/mcp` on the view relays over a websocket to the last tab that opened the view. No tab: HTTP 503. A tab that does not answer within the view's own limit: HTTP 408.
- **A background tab stalls** on queries and screenshots and still answers light calls.
- **The view's endpoint speaks an old revision of the protocol** and answers a notification and `ping` with an error body. This server never forwards the client's handshake; it sends only `tools/list` and `tools/call`.
- **The view's SQL endpoint (`/data/query`) executes writes.** This server never calls it.
- **A URL entry in a plugin is a remote connector** in Claude Desktop and cannot reach a view on this Mac. That is why this is a local server and not a line in `.mcp.json`.

## Results of the view's tools

- Plain text is windowed with `character_offset` and `max_characters`, which are this server's and never forwarded. JSON text is returned whole up to `ToolCatalog.longestStructuredResult` or refused: never cut.
- `update_atlas` has no `character_offset`: a second call would repeat the change.
- An image is limited to one per call, to `longestImageSide` pixels and `largestImageBytes` bytes, through ImageIO.
- `AtlasTools.callDeadline` bounds a whole call and sits inside `ToolStandard.timeLimit`; `BoundsTests` holds the nesting.

## Commands

```bash
swift build
swift build -c release
swift test
./scripts/pack.sh
```

## Architecture

**Apple silicon only, deliberately.** `scripts/pack.sh` builds for arm64 alone and fails if the binary holds any other architecture.

`ViewConnection` is the only door to a view. `LoopbackConnection` implements it over HTTP to `127.0.0.1`; tests implement it with `FakeView`. The door takes a port and a path, never a host.

`ViewToolPolicy` sorts the view's tools into readers and changers by the words in their names. An unrecognised tool is a changer.

## Release checklist

- **Bump the version before packing.** The installer keys on the manifest `version` alone; an unchanged version under a changed build makes it offer only "Uninstall".
- **Three files carry the version and must agree**: `extension/manifest.json`, `EmbeddingAtlasMCPServer.version` in `Server.swift`, and `CFBundleShortVersionString` in `Resources/Info.plist`. `VersionTests` and `pack.sh` both check it.
- **Installing does not restart the server.** The old process keeps answering until Claude Desktop is fully quit and reopened.
- **The text the model reads is code.** Update the server `instructions`, tool and argument descriptions and the manifest `tools` and `long_description` in the same commit as the behaviour. A shipped string never names another server; `CatalogueTests` greps for `-mcp`.

## Diagnostics

Logs go to stderr through `Diagnostics`, which the host captures (Claude Desktop writes it to `~/Library/Logs/Claude/mcp-server-<name>.log`). stdout is the JSON-RPC stream: never `print`. Do not log an argument, a result or an error's description; log a fixed event, the tool name, the error's kind and a duration.
