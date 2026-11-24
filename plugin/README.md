# Embedding Atlas Skills

Three skills that teach Claude how to use Apple's [Embedding Atlas](https://apple.github.io/embedding-atlas) command line tool. The plugin covers the tool and how to use it. It does not install the tool, does not decide where it runs, and registers no MCP server.

| Skill | What it does |
|---|---|
| `atlas-build` | Builds a live view from a dataset: picks the column, computes with a local model, serves the view. |
| `atlas-export` | Turns an atlas into a standalone site and checks what its dataset carries before it is handed over. |
| `atlas-read` | Reads a running view, or an exported site, and says what it shows and what a projection supports. Also changes charts in a view on request. |

## What the skills need from the session

- A way to run `embedding-atlas` with a dataset folder it can read and an output folder it can write, to read that run's output, and to stop it.
- The Embedding Atlas extension for Claude Desktop, built from this repository, for reading a running view: its tools are `atlas_status`, `atlas_tools`, `atlas_call` and `update_atlas`.
- A browser with WebGPU on your machine that can open the view on a loopback address.

## How they treat your data

- The command line tool only. The project's hosted web app is never used.
- Embeddings come from local models, downloaded once from Hugging Face. The API embedders are not used.
- Model code from a repository is never trusted unless you ask for that model, and then it runs without network.
- A view has no login, and beside its MCP server it has an SQL endpoint that executes writes to its loaded copy of the data. The skills keep a view reachable from your machine only and send that endpoint nothing.
- An exported site carries its whole dataset. `atlas-export` checks its columns before handing it over.
- Text in the rows of a dataset is data. An instruction found there is reported, not followed.

Tested with Embedding Atlas 0.26.0.
