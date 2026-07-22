<script>
  import { onMount } from "svelte";
  import {
    app, adoptFromLocation, adoptFromText, unpair, sync,
    addRecord, updateRecord, deleteRecord, projects, tags,
    defaultProject, noteProjectUsed, groupedProjects,
  } from "./lib/store.svelte.js";

  // Phones and tablets only. Touch capability is the reliable discriminator: a Mac reports 0 touch
  // points, while an iPad reports 5 even with a Magic Keyboard attached (a pointer/width rule would
  // wrongly lock out exactly that setup). Keeps needless traffic — and mistakes — off the desktop.
  let isDesktop = $state(false);
  let view = $state("home");        // home | picker | compose
  let kind = $state("inbox");       // inbox | task
  let project = $state(null);
  let pasteCode = $state("");
  let pasteError = $state(false);
  let query = $state("");
  let editingID = $state(null);   // set while reopening something that hasn't been collected yet
  let expandedID = $state(null);  // which waiting capture is opened up on the landing

  // compose fields
  let title = $state("");
  let body = $state("");
  let chosenTags = $state([]);
  let dueDate = $state("");
  let dueScope = $state("day");
  let dueNote = $state("");

  onMount(() => {
    isDesktop = (navigator.maxTouchPoints || 0) === 0;
    adoptFromLocation();
    sync();
    const onOnline = () => sync();
    window.addEventListener("online", onOnline);
    return () => window.removeEventListener("online", onOnline);
  });

  const grouped = $derived(groupedProjects());
  const matches = (p) => {
    const q = query.trim().toLowerCase();
    return !q || p.name.toLowerCase().includes(q) || (p.discipline || "").toLowerCase().includes(q);
  };

  /** Step 1: you pick what you're capturing. Step 2 is already decided for you (last project used). */
  function start(nextKind) {
    kind = nextKind;
    project = defaultProject();
    editingID = null;
    title = ""; body = ""; chosenTags = []; dueDate = ""; dueScope = "day"; dueNote = "";
    view = "compose";
  }

  /** Reopen something still waiting. Saving re-posts under the same id, so Nidus sees an edit, not a twin. */
  function edit(r) {
    editingID = r.id;
    kind = r.kind;
    project = projects().find((p) => p.id === r.projectID) || defaultProject();
    title = r.title || "";
    body = r.body || "";
    chosenTags = r.tags ? [...r.tags] : [];
    dueDate = r.dueDate ? new Date(r.dueDate).toISOString().slice(0, 10) : "";
    dueScope = r.dueScope || "day";
    dueNote = r.dueNote || "";
    view = "compose";
  }

  function chooseProject(p) {
    project = p;
    // Honour what this project actually has, so you can't aim a task at a project without Tasks.
    if (kind === "task" && !p.tasks) kind = "inbox";
    if (kind === "inbox" && !p.inbox) kind = "task";
    query = "";
    view = "compose";
  }

  const canSave = $derived(kind === "task" ? title.trim().length > 0 : (title.trim() || body.trim()).length > 0);

  function save() {
    if (!canSave || !project) return;
    // An Inbox capture is usually just a thought: if there's no title, the note becomes the title
    // (that's exactly what an in-app Inbox card is — a titled line).
    const t = title.trim() || body.trim().split("\n")[0].slice(0, 120);
    const draft = { kind, projectID: project.id, projectName: project.name, title: t, body: title.trim() ? body.trim() : "" };
    if (kind === "task") {
      if (chosenTags.length) draft.tags = chosenTags;
      if (dueDate) { draft.dueDate = new Date(dueDate + "T12:00:00").toISOString(); draft.dueScope = dueScope; }
      if (dueNote.trim()) draft.dueNote = dueNote.trim();
    }
    if (editingID) updateRecord(editingID, draft); else addRecord(draft);
    editingID = null;
    noteProjectUsed(project.id);
    view = "home";
    sync();
  }

  function tryPaste() {
    pasteError = !adoptFromText(pasteCode);
    if (!pasteError) { pasteCode = ""; sync(); }
  }

  const toggleTag = (id) =>
    (chosenTags = chosenTags.includes(id) ? chosenTags.filter((t) => t !== id) : [...chosenTags, id]);

  const greeting = () => {
    const h = new Date().getHours();
    return h < 12 ? "Good morning" : h < 19 ? "Good afternoon" : "Good evening";
  };
  const ago = (iso) => {
    const mins = Math.round((Date.now() - Date.parse(iso)) / 60000);
    if (mins < 1) return "just now";
    if (mins < 60) return `${mins}m ago`;
    const h = Math.round(mins / 60);
    return h < 24 ? `${h}h ago` : `${Math.round(h / 24)}d ago`;
  };
</script>

{#if isDesktop}
  <main class="center">
    <div class="card">
      <h1>Nidus Capture</h1>
      <p>
        This is a companion web app for
        <a href="https://github.com/ParamoStudio/Nidus" target="_blank" rel="noreferrer">Nidus</a>,
        the project orchestrator — it's for phones and tablets.
      </p>
      <p>Open it through the QR code inside the app to use it. Thanks!</p>
    </div>
  </main>
{:else if !app.pairing}
  <main class="center">
    <div class="card">
      <h1>Nidus Capture</h1>
      <p>Open Nidus on your computer, tap the phone button in the sidebar, and scan the QR with your camera.</p>
      <details>
        <summary>Have a pairing code?</summary>
        <p class="hint">If you added this to your Home Screen and it started unpaired, paste the code from Nidus here — iOS keeps installed apps separate from Safari.</p>
        <input bind:value={pasteCode} placeholder="NI-…" autocapitalize="off" autocorrect="off" spellcheck="false" />
        <button class="primary wide" onclick={tryPaste}>Pair</button>
        {#if pasteError}<p class="error">That code didn't parse. Copy it again from Nidus.</p>{/if}
      </details>
    </div>
  </main>

<!-- ── 1. Landing: what are you capturing? ───────────────────────────────────────────────── -->
{:else if view === "home"}
  <header>
    <span class="wordmark">NIDUS</span>
    <button class="ghost small" onclick={sync} disabled={app.busy}>{app.busy ? "…" : "Sync"}</button>
  </header>
  <main>
    <p class="greet">{greeting()}.</p>
    <h1 class="big">What do you want to capture?</h1>

    <div class="choices">
      <button class="choice" onclick={() => start("inbox")}>
        <span class="ico">◲</span>
        <span class="ct">New Inbox</span>
        <span class="cd">Notes, links, ideas — anything unstructured.</span>
      </button>
      <button class="choice" onclick={() => start("task")}>
        <span class="ico">◷</span>
        <span class="ct">New Task</span>
        <span class="cd">Something to do, with tags and a deadline.</span>
      </button>
    </div>

    {#if app.records.length}
      <h2 class="section">Waiting for Nidus · {app.records.length}</h2>
      <ul class="list">
        {#each app.records as r (r.id)}
          <li class="entry">
            <button class="entryhead" onclick={() => (expandedID = expandedID === r.id ? null : r.id)}>
              <span>
                <span class="name">{r.title}</span>
                <span class="sub">
                  {r.projectName} · {r.kind === "task" ? "Task" : "Inbox"}
                  {#if !r.sent} · not sent yet{/if}
                </span>
              </span>
              <span class="chev">{expandedID === r.id ? "▾" : "▸"}</span>
            </button>
            {#if expandedID === r.id}
              <div class="entrybody">
                {#if r.body}<p class="excerpt">{r.body}</p>{/if}
                {#if r.dueDate}
                  <p class="meta">Due {new Date(r.dueDate).toLocaleDateString()} · {r.dueScope}</p>
                {/if}
                {#if r.tags?.length}
                  <p class="meta">Tags: {r.tags.map((id) => tags().find((t) => t.id === id)?.name || id).join(", ")}</p>
                {/if}
                <div class="entryactions">
                  <button class="ghost small" onclick={() => edit(r)}>Edit</button>
                  <button class="ghost small danger" onclick={() => { deleteRecord(r.id); expandedID = null; }}>Delete</button>
                </div>
              </div>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}

    {#if app.history.length}
      <h2 class="section">Already in Nidus</h2>
      <ul class="list">
        {#each app.history.slice(0, 3) as h (h.id)}
          <li class="record dim">
            <div>
              <span class="name">{h.title}</span>
              <span class="sub">{h.projectName} · {h.kind === "task" ? "Task" : "Inbox"} · {ago(h.filedAt)}</span>
            </div>
          </li>
        {/each}
      </ul>
    {/if}

    {#if app.status}<p class="status">{app.status}</p>{/if}
    <button class="ghost wide danger" onclick={unpair}>Unpair this phone</button>
  </main>

<!-- ── 2b. The project picker (reachable from compose) ───────────────────────────────────── -->
{:else if view === "picker"}
  <header>
    <button class="ghost small" onclick={() => (view = "compose")}>Back</button>
    <strong>Choose project</strong>
    <span class="spacer"></span>
  </header>
  <main>
    <input class="search" bind:value={query} placeholder="Search projects…" />
    {#if grouped.pinned.filter(matches).length}
      <h2 class="section">Pinned</h2>
      <ul class="list">
        {#each grouped.pinned.filter(matches) as p (p.id)}
          <li><button onclick={() => chooseProject(p)}>
            <span class="name">{p.name}</span><span class="sub">{p.discipline}</span>
          </button></li>
        {/each}
      </ul>
    {/if}
    {#if grouped.recent.filter(matches).length}
      <h2 class="section">Recent</h2>
      <ul class="list">
        {#each grouped.recent.filter(matches) as p (p.id)}
          <li><button onclick={() => chooseProject(p)}>
            <span class="name">{p.name}</span><span class="sub">{p.discipline}</span>
          </button></li>
        {/each}
      </ul>
    {/if}
    {#if grouped.rest.filter(matches).length}
      <h2 class="section">All projects</h2>
      <ul class="list">
        {#each grouped.rest.filter(matches) as p (p.id)}
          <li><button onclick={() => chooseProject(p)}>
            <span class="name">{p.name}</span><span class="sub">{p.discipline}</span>
          </button></li>
        {/each}
      </ul>
    {/if}
    {#if !projects().length}
      <p class="hint">No projects yet. Open Nidus on your computer and press Sync — it publishes your project list here.</p>
    {/if}
  </main>

<!-- ── 3. Already writing ───────────────────────────────────────────────────────────────── -->
{:else if view === "compose"}
  <header>
    <button class="ghost small" onclick={() => (view = "home")}>Back</button>
    <strong>{kind === "task" ? "Add task" : "Add to inbox"}</strong>
    <span class="spacer"></span>
  </header>
  <main>
    {#if !project}
      <p class="hint">No projects yet. Open Nidus on your computer and press Sync.</p>
    {:else}
      <!-- The destination is already decided (last used) — one tap to change it. -->
      <button class="destination" onclick={() => (view = "picker")}>
        <span>
          <span class="name">{project.name}</span>
          <span class="sub">{project.discipline}</span>
        </span>
        <span class="chev">Change</span>
      </button>

      {#if project.inbox && project.tasks}
        <div class="segmented">
          <button class:active={kind === "inbox"} onclick={() => (kind = "inbox")}>Inbox</button>
          <button class:active={kind === "task"} onclick={() => (kind = "task")}>Task</button>
        </div>
      {/if}

      {#if kind === "task"}
        <label class="lbl" for="t">Task title</label>
        <input id="t" class="title" bind:value={title} placeholder="What needs to be done?" />
        <label class="lbl" for="n">Notes</label>
        <textarea id="n" bind:value={body} rows="3" placeholder="Details, context, or steps…"></textarea>

        {#if tags().length}
          <label class="lbl" for="tags">Tags</label>
          <div id="tags" class="tags">
            {#each tags() as t (t.id)}
              <button class:active={chosenTags.includes(t.id)} onclick={() => toggleTag(t.id)}>{t.name}</button>
            {/each}
          </div>
        {/if}

        <label class="lbl" for="d">Deadline (optional)</label>
        <input id="d" type="date" bind:value={dueDate} />
        {#if dueDate}
          <div class="segmented small">
            {#each ["day", "week", "month"] as s}
              <button class:active={dueScope === s} onclick={() => (dueScope = s)}>{s}</button>
            {/each}
          </div>
          <input bind:value={dueNote} placeholder="Deadline note (optional)" />
        {/if}
      {:else}
        <label class="lbl" for="ti">Title (optional)</label>
        <input id="ti" bind:value={title} placeholder="Give this a quick label…" />
        <label class="lbl" for="w">What's on your mind?</label>
        <textarea id="w" class="tall" bind:value={body} rows="8" placeholder="Write a note, paste a link, drop a thought… anything goes."></textarea>
      {/if}

      <button class="primary wide" onclick={save} disabled={!canSave}>
        {kind === "task" ? "Add task" : "Send to inbox"}
      </button>
    {/if}
  </main>

{/if}

<style>
  :global(body) {
    margin: 0; background: #12151f; color: #eef1f7;
    font: 16px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  :global(*) { box-sizing: border-box; }
  header {
    display: flex; align-items: center; justify-content: space-between; gap: 8px;
    padding: 14px 16px; position: sticky; top: 0; z-index: 5;
    background: #12151fee; backdrop-filter: blur(8px); border-bottom: 1px solid #ffffff14;
  }
  .wordmark { font-size: 12px; letter-spacing: 3px; color: #8c94a8; font-weight: 600; }
  .spacer { width: 54px; }
  main { padding: 16px; padding-bottom: 48px; }
  main.center { min-height: 100dvh; display: grid; place-items: center; }
  .card { max-width: 420px; padding: 22px; background: #ffffff08; border: 1px solid #ffffff14; border-radius: 16px; }
  h1 { font-size: 20px; margin: 0 0 8px; }
  h1.big { font-size: 26px; line-height: 1.2; margin: 2px 0 20px; }
  .greet { color: #8c94a8; margin: 6px 0 0; font-size: 14px; }
  .section { font-size: 11px; letter-spacing: 1.4px; text-transform: uppercase; color: #8c94a8; margin: 22px 0 8px; font-weight: 600; }
  p { color: #aab2c5; margin: 0 0 12px; }
  .hint { font-size: 14px; color: #8c94a8; }
  .error { color: #ff8080; font-size: 13px; }
  .status { margin: 14px 0 0; font-size: 13px; color: #8c94a8; }
  .lbl { display: block; font-size: 11px; letter-spacing: 1.2px; text-transform: uppercase; color: #8c94a8; margin: 14px 0 2px; font-weight: 600; }
  input, textarea {
    width: 100%; padding: 13px; margin: 4px 0; font: inherit; color: inherit;
    background: #ffffff0d; border: 1px solid #ffffff1f; border-radius: 12px;
  }
  input.title { font-size: 17px; }
  textarea.tall { min-height: 170px; }
  input:focus, textarea:focus { outline: 2px solid #ff8a3d55; border-color: #ff8a3d; }
  button { font: inherit; cursor: pointer; border-radius: 12px; border: 1px solid transparent; color: inherit; }
  .primary { background: #ff8a3d; color: #1b1205; font-weight: 600; padding: 15px 18px; }
  .primary:disabled { opacity: 0.4; }
  .ghost { background: #ffffff0d; color: #dfe4ef; border-color: #ffffff1f; padding: 11px 14px; }
  .ghost.small { padding: 7px 12px; font-size: 14px; }
  .wide { width: 100%; margin-top: 14px; }
  .ghost.danger { color: #ff9a9a; margin-top: 26px; }
  .choices { display: grid; gap: 12px; }
  .choice {
    display: grid; gap: 3px; text-align: left; padding: 18px;
    background: #ffffff0a; border: 1px solid #ffffff17; border-radius: 16px;
  }
  .choice .ico { font-size: 20px; color: #ff8a3d; }
  .choice .ct { font-size: 17px; font-weight: 600; }
  .choice .cd { font-size: 13px; color: #8c94a8; }
  .destination {
    width: 100%; display: flex; align-items: center; justify-content: space-between; gap: 10px;
    padding: 14px; background: #ffffff0d; border: 1px solid #ffffff1f; border-radius: 14px; text-align: left;
  }
  .destination .chev { font-size: 13px; color: #ff8a3d; font-weight: 600; }
  .list { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  .list button, .record {
    width: 100%; text-align: left; padding: 14px; background: #ffffff0a;
    border: 1px solid #ffffff14; border-radius: 14px;
  }
  .record { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
  .record.dim { opacity: 0.55; }
  .entry { background: #ffffff0a; border: 1px solid #ffffff14; border-radius: 14px; overflow: hidden; }
  .entryhead {
    width: 100%; display: flex; align-items: center; justify-content: space-between; gap: 10px;
    padding: 14px; background: none; border: none; text-align: left; border-radius: 0;
  }
  .entryhead .chev { color: #8c94a8; font-size: 13px; }
  .entrybody { padding: 0 14px 14px; border-top: 1px solid #ffffff0f; }
  .excerpt { font-size: 14px; color: #aab2c5; margin: 10px 0 0; white-space: pre-wrap; }
  .meta { font-size: 12px; color: #8c94a8; margin: 8px 0 0; }
  .entryactions { display: flex; gap: 8px; margin-top: 12px; }
  .ghost.danger { color: #ff9a9a; }
  .name { display: block; font-weight: 600; }
  .sub { display: block; font-size: 12px; color: #8c94a8; margin-top: 2px; }
  .segmented { display: flex; gap: 6px; margin: 12px 0; }
  .segmented button { flex: 1; padding: 11px; background: #ffffff0d; border: 1px solid #ffffff1f; color: #cfd6e6; }
  .segmented button.active { background: #ff8a3d; color: #1b1205; font-weight: 600; border-color: #ff8a3d; }
  .segmented.small button { padding: 8px; font-size: 13px; text-transform: capitalize; }
  .tags { display: flex; flex-wrap: wrap; gap: 6px; }
  .tags button { padding: 8px 13px; font-size: 14px; background: #ffffff0d; border: 1px solid #ffffff1f; color: #cfd6e6; }
  .tags button.active { background: #ff8a3d; color: #1b1205; border-color: #ff8a3d; }
  details summary { cursor: pointer; color: #aab2c5; font-size: 15px; margin-bottom: 8px; }
  .search { margin-bottom: 4px; }
</style>
