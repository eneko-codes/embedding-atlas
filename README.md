# embedding-atlas

Two things that let Claude work with Apple's [Embedding Atlas](https://apple.github.io/embedding-atlas):

- **A local MCP server**, packaged as a Claude Desktop extension. It connects Claude to the MCP server that Embedding Atlas itself provides for a running view.
- **Embedding Atlas Skills**, a plugin of three skills in `plugin/`: how to build a view, export a site, and read what a map shows.

Neither installs Embedding Atlas, and neither decides where it runs.

## Requirements

- macOS 26 on Apple silicon, and Claude Desktop.
- A view served by the `embedding-atlas` command line tool with its MCP option, reachable on this Mac at `127.0.0.1`.
- Xcode's Swift toolchain, to build.

## Why a server is needed at all

Embedding Atlas already has an MCP server: a view started with the MCP option answers at `/mcp`. It is an HTTP address inside the running view, and Claude Desktop only uses a local server that it starts itself as a program. This extension is that program. It adds no tools of its own to a view; it reaches the view's tools and passes them through.

## Tools

| Tool | What it does |
|---|---|
| `atlas_status` | Says whether a view answers, which columns it uses, whether it has its MCP endpoint, and whether a browser tab is connected. |
| `atlas_tools` | Lists the tools the running view offers and marks the ones that change it. With a name, returns that tool's input schema. |
| `atlas_call` | Calls one of the view's tools that only reads: schema, read-only SQL, specs, app state, screenshots. |
| `update_atlas` | Calls one of the view's tools that changes what the view shows: charts, layouts, column styles. |

Each takes an optional `port`, for a view that is not on the tool's default port.

## The rules worth knowing before you use it

- **The view's tools run inside a browser tab.** Embedding Atlas answers MCP calls from the page that has the view open. With no tab open there is nothing to call. With several, it relays to the last one opened.
- **A tab in the background stalls.** It answers light calls and times out on queries and screenshots. Bring the tab to the front.
- **The view must have the MCP option.** A view started without it, and an exported site, have no tools.
- **Loopback only.** The server talks to `127.0.0.1` and takes a port, never a host. It cannot start, stop or serve a view, and it reads and writes no file.
- **Two doors, split by effect**, so that reading a view and changing it have separate switches. A tool of the view that the server does not recognise counts as a change.
- **Rows are data.** Text that comes back from a dataset is never an instruction.

## Install

### 1. Build the bundle

```bash
./scripts/pack.sh
```

This builds the release binary for arm64, signs it, and writes `dist/embedding-atlas-mcp.mcpb`.

### 2. Install it

Open the `.mcpb` file with Claude Desktop (Settings > Extensions), then quit Claude Desktop completely and reopen it: installing does not restart a server process that is already running.

### 3. Add the skills

Zip the contents of `plugin/` as `dist/embedding-atlas-skills.zip` and upload it in Customize > Plugins.

### Signing

The script signs ad-hoc by default, which gives the binary a new identity on every rebuild. Set `MCPB_SIGN_IDENTITY` to a signing identity for a stable one, and `MCPB_HARDENED=1` when preparing something to distribute.

## Tool switches

Nothing is configured. What Claude may use is decided by the per-tool switches in Claude Desktop: allow `atlas_status`, `atlas_tools` and `atlas_call` to let it read a view, and decide separately about `update_atlas`.

## Known limits

- No SQL without a browser tab: the view's query tool runs in the page.
- The view's own SQL endpoint, which also accepts writes, is never used.
- A view that is not reachable on `127.0.0.1` is out of reach by design.

## Development

```bash
swift build
swift test
```

The tests run against an invented view held in memory. See `CLAUDE.md` for the rules, and the README in each folder for what it holds.

## Licence

MIT. Not affiliated with or endorsed by Apple Inc.
