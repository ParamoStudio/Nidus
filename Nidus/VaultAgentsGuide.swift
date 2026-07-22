//
//  VaultAgentsGuide.swift
//  Nidus
//
//  `AGENTS.md`, written at the vault root for any AI a user points at their vault (a "second brain"
//  read, a coding agent, whatever) — generic orientation, never project-specific content. It explains
//  the vault's structure and every tool's on-disk format so a reading AI can find and correctly parse
//  a project's content without guessing. Written by `VaultStore.ensureConfigExists()`, alongside the
//  vault marker and `nidus.json` — every vault (including other users' vaults) gets it automatically.
//  Canonical: rewritten whenever its shipped content differs from what's on disk (same pattern as the
//  built-in micro-tools' seed), so improvements to this guide reach existing vaults too.
//

import Foundation

enum VaultAgentsGuide {
    static let fileName = "AGENTS.md"

    static let content = """
    # Reading a Nidus vault

    This file is generated and maintained by the Nidus app — generic orientation, not project content.
    It's here so an AI (a "second brain" assistant, a coding agent, anything you've pointed at this
    folder) can find and correctly interpret what's in this vault without guessing at the format.

    Nidus is a filesystem-as-truth personal knowledge / project-management app: every file here is
    plain text or JSON, human-readable, and is the actual data — there's no hidden database. Reading
    the files IS reading the app's state.

    ## 1. Structure

    ```
    <vault>/
      nidus.json              ← the index: every discipline → every project → its tool layout
      AGENTS.md                ← this file
      _tools/                  ← optional user-installed tools (.js), see §5
      _library/<tool-id>/      ← optional cross-project banks a tool opted into, see §5
      <discipline-folder>/
        <project-folder>/
          inbox.md, ideas.md, tasks-todo.md, tasks-done.md, event-log.md, blueprint.json,
          Notebook/, _assets/, …           ← only the files/folders that project's tools actually use
    ```

    A "discipline" is a top-level grouping (e.g. "Ceramics", "Programming"); a "project" lives inside
    one. Start with `nidus.json` to find your way to a specific project's folder:

    ```jsonc
    {
      "disciplines": [
        { "id": "...", "name": "...", "folder": "...", "projects": [
          { "id": "...", "name": "...", "folder": "...",       // project dir = <vault>/<discipline.folder>/<project.folder>/
            "description": "...",                                // free text the human wrote about the project
            "layout": { "grid": [ { "tool": "inbox", ... }, { "tool": "ideas", ... }, ... ] } }
        ] }
      ]
    }
    ```

    `layout.grid[].tool` tells you WHICH tools this project actually has (not every project has every
    tool) and therefore which files to expect in its folder — cross-reference against §3.

    ## 2. The universal "card" format (most tools use this)

    Inbox, Ideas, Tasks, Event Log, installed tools, and cross-project library banks all store their
    content the same way: a `.md` file is a short free-text header (ignore it — it's just a label),
    followed by zero or more **cards**:

    ```
    ## <title>
    <!-- nidus:{"id":"...","created":"2026-06-25T15:54:07Z","modified":"...","origin":"...","images":[],"links":[],"extra":{}} -->

    <body — freeform Markdown, may be empty>
    ```

    The `<!-- nidus:{...} -->` line is a **hidden JSON metadata comment** — not a stray HTML comment,
    it's the card's structured data. Fields: `id` (stable UUID), `created`/`modified` (ISO-8601),
    `origin` (which tool it was last in — cards move between tools, so this is informational, not
    authoritative), `images` (relative asset paths), `links` (`[{title,url}]`), and **`extra`** — an
    open string→string dictionary where each tool stashes its own fields (due dates, tags, status…).
    You don't need to know a tool's specific `extra` keys to read a card's title/body/dates; you DO need
    them to fully understand structured fields — see §3 for what each built-in tool puts there.

    A file can hold many cards; a card's body is itself Markdown and may contain its own `##` headings
    without being mistaken for a new card (only a `##` line immediately followed by a metadata comment
    starts a new card).

    ## 3. What each tool means, and where to look for what

    | Tool | File(s) | What it represents | Notable `extra` keys |
    |---|---|---|---|
    | **Inbox** | `inbox.md` | Raw, unsorted capture — "everything lands here to be triaged." Treat as noisy/low-signal; useful for chronology, not conclusions. | — |
    | **Ideas** | `ideas.md` | Developed, deliberately-kept notes — one step more curated than Inbox. | — |
    | **Task Manager** | `tasks-todo.md` | Active tasks. | `tags` (comma-separated), `dueDate` (ISO-8601), `dueScope` (`day`\\|`week`\\|`month`), `dueNote` |
    | **Task Archive** | `tasks-done.md` | Completed tasks (same shape as above — a task's *status* is which file it's in, not a field). | same as Task Manager |
    | **Event Log** | `event-log.md` | A chronological log of decisions/iterations/milestones/abandoned branches — "a light git log" for the project. **Often the best single file for "what happened and why" questions.** | `date` (ISO-8601), `type` (`decision`\\|`iteration`\\|`milestone`\\|`abandoned`), `parent` (id of a related event, optional) |
    | **Reference Board** | a linked image folder (path is in `nidus.json`, NOT necessarily inside the vault) + a hidden `.nidus-references` JSON manifest | A visual mood board. The manifest's `notes: {filename: "why is it here"}` is the only text content — the images themselves carry the rest. | n/a — different format, see manifest above |
    | **Blueprint** | `blueprint.json` | **The project's current stated direction/goal** — "given everything we know, what are we actually making." Different format (NOT the card format): `{templateName, fields:[{label,value,included}], version, approvedAt, activity:[...]}`. Only `included:true` fields are meant to be shown/considered current. **Read this FIRST when asked what a project is/was about** — it's the human's own deliberate summary, updated as the project evolved (`activity` is a short changelog of when it was revised). | n/a |
    | **Notebook** | a `Notebook/` subfolder | A document library — NOT the card format. Real `.md`/`.markdown` files (small YAML frontmatter: `title`/`id`/`created`, then plain Markdown body) plus imported documents (`.pdf .txt .docx .odt .pages .rtf`) copied in as-is. Subfolders are user-named groups. A hidden `.nidus-notebook` JSON file only stores pin order — ignore it. | n/a |

    ## 4. A practical reading order for "what was/is this project about"

    1. **`blueprint.json`** if present — the human's own deliberate, current-as-of-last-edit summary.
       Read `activity` for a timeline of when the direction changed.
    2. **`nidus.json`**'s `description` for that project — a short, rarely-updated one-liner from
       creation time.
    3. **`Notebook/`** — any real documents/notes the human wrote deliberately.
    4. **`event-log.md`** — chronological decisions/milestones, if the project uses it.
    5. **`ideas.md`** — curated thinking that didn't make it into a document.
    6. **`tasks-done.md`** — what was actually completed (concrete, dated evidence of work).
    7. **`inbox.md`** and **Reference Board** last — raw/visual material, lower signal, useful for
       specific detail lookups once you already have the shape of the project from the above.

    Use each card's/event's `created`/`modified` timestamps to reconstruct chronology across files —
    nothing here is globally ordered except within a single file.

    ## 5. Extensibility (you may see tools not listed above)

    Nidus supports **user-installed tools** (`_tools/<id>.js`) that add their own card-format `.md`
    file(s) with their own `extra` schema — e.g. a ceramics vault might have a custom "Glaze Recipes"
    tool with `extra.status`/`extra.surface`/`extra.cone`. §2's card format still applies; you just
    won't know the specific `extra` keys' meaning without more context (their names are usually
    self-explanatory, or the tool's own `_tools/<id>.js` documents its schema in a comment at the top).

    Some tools also opt into a **cross-project bank**: `_library/<tool-id>/library.md`, same card
    format, `extra._owner` marks which project owns each entry (informational).

    ## 6. What NOT to assume

    - File presence varies per project — check `layout.grid` (§1) rather than assuming every file exists.
    - `origin` on a card is where it currently sits or last came from, not a permanent classification.
    - Nothing here is a database index — there's no cross-project search structure; each project's
      folder is self-contained and must be read directly.
    """
}
