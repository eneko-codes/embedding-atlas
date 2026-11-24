---
name: "atlas-export"
description: "Turns an Embedding Atlas into a standalone site (a folder or zip that any static HTTP server can serve) with the export option of Apple's embedding-atlas command line tool, deciding which rows and columns the site carries and checking its dataset before it is handed over. Use when he asks to export an atlas, for a site, folder or zip of one («exporta el atlas», «standalone», «static site», «para compartir»), to trim, rebuild or re-export a site made before, to carry the charts of a view into a site, or to open a site exported before. Not for computing or serving a live atlas view from a dataset, nor for saying what an atlas shows, nor for publishing or hosting the site anywhere."
---

# Atlas export

Producing an Embedding Atlas site that can be kept or handed over, and making sure it carries only what its reader should get. An exported site holds its whole dataset in one file that anyone who can open the site can download.

## Tools

- **`embedding-atlas`** with its export option, to a folder or a zip. An export is the same command as a live view with exporting in place of serving. Read `--help` on the day.
  - To export the map of an existing view, repeat its command exactly: same input, query, sample, model and seed. An identical command reuses the tool's cached projection. Anything else, a row filter included, or a lost cache with no seed fixed, computes a new map: tell him when the site's map is not the view's.
  - Name the input column or the coordinate columns on the command line: with neither the tool opens a prompt and crashes where there is no terminal. The API embedder is never used.
- **The query option** decides what the site carries. It runs after the tool has added a column holding the input's path as typed, and before the embedding step and before the row index is added: it can drop the path column and any column the embedding does not need, and it cannot drop a column the embedding needs.
- **Columns the tool adds**, on every run: the input's path and a row index; when it computes, the two coordinates and a neighbours column; a split column for a Hugging Face dataset; and, when sampling, a column with each row's position in the source. The site needs the row index, the coordinates and the neighbours. The neighbours column refers to rows by position.
- **DuckDB**, a Python module in the tool's own Python, reads a dataset file's columns and rows in one query.
- **Limits of a site.** It needs an HTTP server: its `index.html` opened as a file stays blank. The tool writes into an existing folder without asking.

## Procedure

1. **Decide what the site carries** before running anything: which rows, and which columns. Columns he named to drop are dropped and the rest of his columns stay. The path column never goes in: it publishes his folder names. Vectors stay out unless he asks for them. When unsure about a column, ask.
2. **Charts and layouts** of a view go into the site through its saved app state, passed to the run that produces the final site. If he wants them and no state file exists, read the state with the view's own app-state tool, through `atlas_call`, from the tab that holds his charts, never from a tab opened for the purpose, and save it as a file. With no view running, ask him for the file or export without charts. A chart built on a column that is being dropped will not render: tell him before exporting.
3. **One pass, from the source,** when everything to drop is something the embedding does not need: the query filters the rows and leaves out the path column and the unwanted columns.
4. **Two passes** when a column the embedding needs must not be in the site (the vectors it was computed from, the text itself), or when the source is a site exported before:
   - First pass: export from the source to a scratch folder, filtering rows here if needed and leaving the path column out. This output still holds what must not be published: delete it once the site is checked, or keep it as the source of later rebuilds only if he wants that, and say which.
   - Read the first pass's dataset file for its column names before writing the next query.
   - Second pass: export from that dataset file, naming its coordinate and neighbour columns in place of the input column, plus the same text or image option as before, so that labels, search and tooltips survive and no model is loaded. Its query leaves out the unwanted columns, the path column the tool adds again, and the row index already in the file, which the tool would otherwise double.
   - The second-pass query drops columns, never rows: a row filter there leaves the neighbours pointing at the wrong rows.
5. **Export the final site into a new, empty folder** or a new zip, in the folder he named; ask where when he named none.
6. **Check the exported dataset**, not the command. The dataset file and the metadata file sit in the site's data folder; unpack a zip to a scratch folder to read them. Check the column list, the row count, and that the highest neighbour id is below the row count; no path of his may appear in either file. A column that is neither one he kept nor one the site needs is a finding to report, not to ignore.
7. **Load the site once** over HTTP from any static server that others cannot reach: the charts render, the map draws (or the reply says the map was not seen, for lack of WebGPU), and the page requests nothing outside its own address. Stop that server afterwards. Opening a site made before is this step alone, with the server left running while he looks.

## Before finishing

- [ ] The exported dataset holds no path column, no doubled column and nothing he did not want published; the reply lists the columns it carries.
- [ ] Rows were filtered in the first pass only, and the first pass's output is deleted or the reply says it was kept.
- [ ] The site was loaded over HTTP once, and the reply says whether a server is still running.
- [ ] The reply says where the site is, that it needs an HTTP server, and that whoever can open it can read its whole dataset.

## Files

No files beyond this one.
