<script>
  import { onMount } from "svelte";
  import Metaball from "./lib/Metaball.svelte";
  import ProjectIcon from "./lib/ProjectIcon.svelte";
  import DeadlinePicker from "./lib/DeadlinePicker.svelte";
  import {
    app, adoptFromLocation, adoptFromText, unpair, sync, toggleTheme,
    addRecord, updateRecord, deleteRecord, projects, tags, userName,
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
  let showHelp = $state(false);

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

  // The appearance lives on the root element so the page background reacts too, not just the app.
  $effect(() => {
    document.documentElement.dataset.theme = app.theme;
  });

  const grouped = $derived(groupedProjects());
  const searching = $derived(query.trim().length > 0);
  let openDiscipline = $state(null);

  /** Everything not already surfaced above, grouped by discipline so the long tail stays folded away. */
  const disciplines = $derived.by(() => {
    const surfaced = new Set([...grouped.pinned, ...grouped.recent.slice(0, 3)].map((p) => p.id));
    const byName = new Map();
    for (const p of projects()) {
      if (surfaced.has(p.id)) continue;
      const name = p.discipline || "Other";
      if (!byName.has(name)) byName.set(name, []);
      byName.get(name).push(p);
    }
    return [...byName.entries()]
      .map(([name, list]) => ({ name, projects: list }))
      .sort((a, b) => a.name.localeCompare(b.name));
  });
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
  /** A recent project's subtitle: when you last captured into it, falling back to its discipline. */
  const lastUsed = (p) => (app.usedAt[p.id] ? `Last used ${ago(app.usedAt[p.id])}` : p.discipline);
</script>

{#snippet projectRow(p, subtitle)}
  <button class="row" onclick={() => chooseProject(p)}>
    <ProjectIcon project={p} size={38} />
    <span class="grow"><span class="name">{p.name}</span><span class="sub">{subtitle ?? p.discipline}</span></span>
    {#if p.pinned}<span class="pin" aria-hidden="true">⚲</span>{:else}<span class="chev">›</span>{/if}
  </button>
{/snippet}

{#snippet sphere(p)}
  <button class="sphere" onclick={() => chooseProject(p)}>
    <ProjectIcon project={p} size={78} />
    <span class="spherelabel">{p.name}</span>
  </button>
{/snippet}

{#if isDesktop}
  <main class="center">
    <div class="glass pad">
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
    <div class="glass pad">
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
    <span class="controls">
      <button class="circle" onclick={toggleTheme} aria-label="Toggle appearance">
        {#if app.theme === "dark"}
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z" />
          </svg>
        {:else}
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round">
            <circle cx="12" cy="12" r="4.2" />
            {#each [0, 45, 90, 135, 180, 225, 270, 315] as a}
              <line x1="12" y1="2.6" x2="12" y2="5" transform="rotate({a} 12 12)" />
            {/each}
          </svg>
        {/if}
      </button>
      <a class="circle" href="https://github.com/ParamoStudio/Nidus" target="_blank" rel="noreferrer" aria-label="Nidus on GitHub">
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.61.07-.61 1 .07 1.53 1.03 1.53 1.03.9 1.53 2.34 1.09 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.65 0 0 .84-.27 2.75 1.02a9.5 9.5 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.38.2 2.4.1 2.65.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.69-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2Z" />
        </svg>
      </a>
      <button class="circle" onclick={() => (showHelp = true)} aria-label="What is Nidus?">?</button>
    </span>
  </header>
  <main>
    <div class="hero"><Metaball size={112} /></div>
    <p class="greet">{greeting()}{userName() ? `, ${userName()}` : ""}.</p>
    <h1 class="big">What do you want to capture?</h1>

    <div class="choices">
      <button class="choice glass" onclick={() => start("inbox")}>
        <span class="badge">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
            <path d="M3 13h4l1.6 2.6h6.8L17 13h4" />
            <path d="M4.6 6.2 3 13v4.4A1.6 1.6 0 0 0 4.6 19h14.8a1.6 1.6 0 0 0 1.6-1.6V13l-1.6-6.8A1.6 1.6 0 0 0 17.8 5H6.2a1.6 1.6 0 0 0-1.6 1.2Z" />
          </svg>
          <span class="plus">+</span>
        </span>
        <span class="ct">New Inbox</span>
        <span class="cd">Send notes, links, ideas, or anything unstructured.</span>
      </button>
      <button class="choice glass" onclick={() => start("task")}>
        <span class="badge">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="8.4" />
            <path d="m8.4 12.2 2.6 2.6 4.6-5.2" />
          </svg>
          <span class="plus">+</span>
        </span>
        <span class="ct">New Task</span>
        <span class="cd">Create a task with details, tags, and a due date.</span>
      </button>
    </div>

    {#if app.records.length}
      <h2 class="section">Waiting for Nidus · {app.records.length}</h2>
      <ul class="list">
        {#each app.records as r (r.id)}
          <li class="entry glass">
            <button class="entryhead" onclick={() => (expandedID = expandedID === r.id ? null : r.id)}>
              <span class="grow">
                <span class="name">{r.title}</span>
                <span class="sub">
                  {r.projectName} · {r.kind === "task" ? "Task" : "Inbox"}
                  {#if !r.sent} · not sent yet{/if}
                </span>
              </span>
              <span class="chev">{expandedID === r.id ? "⌄" : "›"}</span>
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
      <ul class="log glass">
        {#each app.history.slice(0, 3) as h (h.id)}
          <li>
            <span class="dot" aria-hidden="true"></span>
            <span class="grow"><span class="logtitle">{h.title}</span><span class="sub">{h.projectName} · {ago(h.filedAt)}</span></span>
          </li>
        {/each}
      </ul>
    {/if}

    <div class="footer">
      <button class="ghost wide" onclick={sync} disabled={app.busy}>{app.busy ? "Syncing…" : "Sync manually"}</button>
      {#if app.status}<p class="status">{app.status}</p>{/if}
      <button class="unpair" onclick={unpair}>Unpair this phone</button>
    </div>
  </main>

<!-- ── 2b. The project picker ───────────────────────────────────────────────────────────── -->
{:else if view === "picker"}
  <header>
    <button class="circle" onclick={() => (view = "compose")} aria-label="Back">‹</button>
    <strong class="htitle">Choose Project</strong>
    <span class="controls"><span class="circle ghostly"></span></span>
  </header>
  <main>
    <div class="searchwrap">
      <svg class="searchicon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round">
        <circle cx="11" cy="11" r="6.4" /><path d="m15.8 15.8 4 4" />
      </svg>
      <input class="search" bind:value={query} placeholder="Search projects…" />
    </div>

    {#if searching}
      <!-- While searching, groups only get in the way: one flat list of what matches. -->
      <ul class="list">
        {#each projects().filter(matches) as p (p.id)}
          <li>{@render projectRow(p, null)}</li>
        {/each}
      </ul>
      {#if !projects().filter(matches).length}
        <p class="hint">Nothing matches “{query}”.</p>
      {/if}
    {:else}
      {#if grouped.pinned.length}
        <h2 class="section">Pinned</h2>
        <!-- The greeting panel's row of glass spheres: your anchored projects, one tap away. -->
        <div class="spheres">
          {#each grouped.pinned as p (p.id)}{@render sphere(p)}{/each}
        </div>
      {/if}

      {#if grouped.recent.length}
        <h2 class="section">Recent</h2>
        <ul class="list">
          {#each grouped.recent.slice(0, 3) as p (p.id)}<li>{@render projectRow(p, lastUsed(p))}</li>{/each}
        </ul>
      {/if}

      {#if disciplines.length}
        <h2 class="section">All projects</h2>
        <ul class="list">
          {#each disciplines as d (d.name)}
            <li class="entry glass">
              <button class="entryhead" onclick={() => (openDiscipline = openDiscipline === d.name ? null : d.name)}>
                <span class="grow">
                  <span class="name">{d.name}</span>
                  <span class="sub">{d.projects.length} project{d.projects.length === 1 ? "" : "s"}</span>
                </span>
                <span class="chev">{openDiscipline === d.name ? "⌄" : "›"}</span>
              </button>
              {#if openDiscipline === d.name}
                <div class="entrybody">
                  <ul class="list nested">
                    {#each d.projects as p (p.id)}<li>{@render projectRow(p, null)}</li>{/each}
                  </ul>
                </div>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}

      {#if !projects().length}
        <p class="hint">No projects yet. Open Nidus on your computer and press Sync — it publishes your project list here.</p>
      {/if}
    {/if}
  </main>

<!-- ── 3. Already writing ───────────────────────────────────────────────────────────────── -->
{:else if view === "compose"}
  <header>
    <button class="circle" onclick={() => (view = "home")} aria-label="Back">‹</button>
    <strong class="htitle">{kind === "task" ? "Add Task" : "Add Inbox"}</strong>
    <span class="controls"><span class="circle ghostly"></span></span>
  </header>
  <main>
    {#if !project}
      <p class="hint">No projects yet. Open Nidus on your computer and press Sync.</p>
    {:else}
      <!-- The destination is already decided (last used) — one tap to change it. -->
      <button class="destination glass" onclick={() => (view = "picker")}>
        <ProjectIcon {project} size={34} />
        <span class="grow"><span class="name">{project.name}</span></span>
        <span class="chev">⌄</span>
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
        <textarea id="n" bind:value={body} rows="4" placeholder="Details, context, or steps…"></textarea>

        {#if tags().length}
          <span class="lbl">Tags</span>
          <div class="tags">
            {#each tags() as t (t.id)}
              <button class:active={chosenTags.includes(t.id)} onclick={() => toggleTag(t.id)}>{t.name}</button>
            {/each}
          </div>
        {/if}

        <span class="lbl">Deadline (optional)</span>
        <DeadlinePicker bind:date={dueDate} bind:scope={dueScope} />
        {#if dueDate}
          <input bind:value={dueNote} placeholder="Deadline note (optional)" />
        {/if}
      {:else}
        <label class="lbl" for="ti">Title (optional)</label>
        <input id="ti" bind:value={title} placeholder="Give this a quick label…" />
        <label class="lbl" for="w">What's on your mind?</label>
        <textarea id="w" class="tall" bind:value={body} rows="8" placeholder="Write a note, paste a link, drop a thought… anything goes."></textarea>
      {/if}

      <button class="primary wide" onclick={save} disabled={!canSave}>
        {kind === "task" ? "Add Task" : "Send to Inbox"}
      </button>
    {/if}
  </main>

{/if}


<!-- ── The "?" sheet: what this thing is, and the one trap worth warning about ──────────── -->
{#if showHelp}
  <!-- Closing on the scrim itself (not on anything inside it) keeps the sheet handler-free. -->
  <div class="scrim" role="presentation" onclick={(e) => { if (e.target === e.currentTarget) showHelp = false; }}>
    <div class="sheet glass" role="dialog" aria-modal="true" aria-label="About Nidus Capture">
      <h2>Nidus Capture</h2>
      <p>
        <strong>Nidus</strong> is a project orchestrator on your computer: every project is a real folder
        of Markdown files that you own, arranged as a workspace of small tools.
      </p>
      <p>
        This web app is its <strong>capture end</strong>. It doesn't show your projects' contents and it
        never will — it exists so an idea or a task can reach the right project while you're away from the
        computer. You write, it queues, and Nidus files it into the actual Inbox or Task Manager next time
        it's open.
      </p>
      <p>
        It works offline. A capture stays on this phone until Nidus has really filed it, so nothing is lost
        in a tunnel or a bad signal.
      </p>
      <h3>Added it to your Home Screen and it asks to pair again?</h3>
      <p>
        That's iOS, not a bug: an installed web app gets its own private storage, so the pairing you made in
        Safari is invisible to it. Open Nidus on your computer → the phone button in the sidebar → copy the
        pairing code, and paste it here. Once is enough.
      </p>
      <button class="ghost wide" onclick={() => (showHelp = false)}>Got it</button>
    </div>
  </div>
{/if}

<style>
  /* ── The Nidus design language ────────────────────────────────────────────────────────────
     Same palette as the app (GlassStyle.swift): a contained warm→cool ambient gradient with a
     blue bloom, and frosted glass surfaces floating on top of it. Dark is the default. */
  :global(:root) {
    --g1: #191a22; --g2: #141519; --g3: #1a1c28;
    --bloom-a: #3a5bff3d; --bloom-b: #7e96ff2e;
    --text: #eef1f7; --dim: #939cb2;
    --glass: #ffffff0f; --glass-edge: #ffffff1f; --glass-strong: #ffffff17;
    --field: #ffffff0a; --field-edge: #ffffff1c;
    --sphere-edge: #ffffff4d; --sphere-glare: #ffffff40;
    --accent: #6d8bff; --accent-soft: #3a5bff33;
    --cta-a: #3f57d8; --cta-b: #6d5fce;
    --blob-hi: #ffffff; --blob-mid: #e4eaf8; --blob-lo: #b9c6e6; --blob-glow: #93a6e055;
    --danger: #ff9a9a; --scrim: #141519d1; --sheet: #1b1d27f2;
    color-scheme: dark;
  }
  :global(:root[data-theme="light"]) {
    --g1: #f2efea; --g2: #e8eaf4; --g3: #dfe4f4;
    --bloom-a: #3a5bff2e; --bloom-b: #7e96ff24;
    --text: #171a24; --dim: #616a80;
    --glass: #ffffff8c; --glass-edge: #ffffffcc; --glass-strong: #ffffffa6;
    --field: #ffffff99; --field-edge: #00000014;
    --sphere-edge: #00000024; --sphere-glare: #ffffffcc;
    --accent: #2f4be0; --accent-soft: #3a5bff26;
    --cta-a: #4257de; --cta-b: #6f60d6;
    --blob-hi: #4a5570; --blob-mid: #2c3345; --blob-lo: #171a24; --blob-glow: #6d7fbd44;
    --danger: #c23b3b; --scrim: #e8eaf4cc; --sheet: #f6f7fcf7;
    color-scheme: light;
  }

  :global(body) {
    margin: 0;
    min-height: 100dvh;
    color: var(--text);
    font: 16px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    -webkit-font-smoothing: antialiased;
    /* The ambient gradient, blooms first so they read over the base wash. */
    background:
      radial-gradient(120% 70% at 92% 0%, var(--bloom-a), transparent 62%),
      radial-gradient(100% 60% at 45% 70%, var(--bloom-b), transparent 66%),
      linear-gradient(135deg, var(--g1), var(--g2) 52%, var(--g3));
    background-attachment: fixed;
  }
  :global(*) { box-sizing: border-box; }

  /* Glass: a translucent surface with a lit edge — never a flat grey panel. */
  .glass {
    background: var(--glass);
    border: 1px solid var(--glass-edge);
    -webkit-backdrop-filter: blur(22px) saturate(140%);
    backdrop-filter: blur(22px) saturate(140%);
    border-radius: 20px;
  }
  .pad { padding: 22px; max-width: 420px; }

  header {
    display: flex; align-items: center; justify-content: space-between; gap: 10px;
    padding: 16px; position: sticky; top: 0; z-index: 5;
    -webkit-backdrop-filter: blur(18px); backdrop-filter: blur(18px);
    background: linear-gradient(to bottom, var(--scrim), transparent);
  }
  .wordmark { font-size: 13px; letter-spacing: 3px; color: var(--dim); font-weight: 600; }
  .htitle { font-size: 17px; font-weight: 600; }
  .controls { display: flex; align-items: center; gap: 8px; }
  /* The app's round icon buttons (IconButton.swift). */
  .circle {
    width: 38px; height: 38px; flex: none; border-radius: 50%;
    display: grid; place-items: center; font-size: 17px; text-decoration: none;
    color: var(--text); background: var(--glass); border: 1px solid var(--glass-edge);
    -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);
  }
  .circle svg { width: 19px; height: 19px; }
  .circle.ghostly { background: none; border-color: transparent;
    -webkit-backdrop-filter: none; backdrop-filter: none; } /* balances the centred title */

  main { padding: 4px 16px 48px; }
  main.center { min-height: 100dvh; display: grid; place-items: center; padding: 16px; }
  h1 { font-size: 20px; margin: 0 0 8px; }
  h1.big { font-size: 27px; line-height: 1.2; margin: 4px 0 22px; font-weight: 600; }
  .greet {
    color: var(--text); opacity: 0.7; margin: 8px 0 0; font-size: 15px;
    text-decoration: underline; text-underline-offset: 3px;
  }
  .hero { display: grid; place-items: center; padding: 14px 0 4px; }
  .section {
    font-size: 11px; letter-spacing: 1.5px; text-transform: uppercase;
    color: var(--dim); margin: 26px 0 10px; font-weight: 600;
  }
  p { color: var(--dim); margin: 0 0 12px; }
  a { color: var(--accent); }
  .hint { font-size: 14px; }
  .error { color: var(--danger); font-size: 13px; }

  /* ── Capture choices ─────────────────────────────────────────────────────────────────── */
  .choices { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .choice { display: grid; gap: 4px; text-align: left; padding: 18px 16px 16px; }
  .badge { position: relative; display: inline-grid; place-items: center; width: 30px; height: 30px; margin-bottom: 8px; color: var(--text); }
  .badge svg { width: 27px; height: 27px; }
  /* The "+" that makes these read as CREATE, not as a section header. */
  .plus {
    position: absolute; right: -7px; bottom: -4px; width: 16px; height: 16px; border-radius: 50%;
    display: grid; place-items: center; font-size: 12px; font-weight: 700; line-height: 1;
    background: var(--accent); color: #fff;
  }
  .choice .ct { font-size: 16px; font-weight: 600; }
  .choice .cd { font-size: 12.5px; color: var(--dim); line-height: 1.35; }

  /* ── Rows, spheres, lists ────────────────────────────────────────────────────────────── */
  .list { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  .row {
    width: 100%; display: flex; align-items: center; gap: 12px; text-align: left; padding: 11px 14px;
    background: var(--glass); border: 1px solid var(--glass-edge); border-radius: 16px;
    -webkit-backdrop-filter: blur(18px); backdrop-filter: blur(18px);
  }
  .grow { flex: 1; min-width: 0; }
  .name { display: block; font-weight: 600; }
  .sub { display: block; font-size: 12.5px; color: var(--dim); margin-top: 2px; }
  .chev { color: var(--dim); font-size: 18px; }
  .pin { color: var(--accent); font-size: 15px; }

  .spheres { display: flex; flex-wrap: wrap; gap: 6px; }
  .sphere {
    background: none; border: none; padding: 4px; width: 96px;
    display: grid; justify-items: center; gap: 9px;
  }
  .spherelabel { font-size: 13px; color: var(--dim); line-height: 1.25; }

  .entry { overflow: hidden; }
  .entryhead {
    width: 100%; display: flex; align-items: center; gap: 10px;
    padding: 13px 14px; background: none; border: none; text-align: left; border-radius: 0;
  }
  .entrybody { padding: 0 14px 14px; border-top: 1px solid var(--glass-strong); }
  .excerpt { font-size: 14px; color: var(--dim); margin: 11px 0 0; white-space: pre-wrap; }
  .meta { font-size: 12px; color: var(--dim); margin: 8px 0 0; }
  .entryactions { display: flex; gap: 8px; margin-top: 12px; }
  .list.nested { margin-top: 10px; }
  .log { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }

  /* ── Fields ──────────────────────────────────────────────────────────────────────────── */
  .lbl {
    display: block; font-size: 11px; letter-spacing: 1.3px; text-transform: uppercase;
    color: var(--dim); margin: 18px 0 6px; font-weight: 600;
  }
  input, textarea {
    width: 100%; padding: 14px; font: inherit; color: inherit;
    background: var(--field); border: 1px solid var(--field-edge); border-radius: 14px;
    -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);
  }
  input.title { font-size: 17px; }
  textarea { resize: vertical; }
  textarea.tall { min-height: 210px; }
  input:focus, textarea:focus {
    outline: none; border-color: var(--accent); box-shadow: 0 0 0 4px var(--accent-soft);
  }
  ::placeholder { color: var(--dim); opacity: 0.85; }

  .searchwrap { position: relative; display: flex; align-items: center; }
  .searchicon { position: absolute; left: 16px; width: 18px; height: 18px; color: var(--dim); pointer-events: none; }
  .search { padding-left: 44px; border-radius: 999px; }

  /* ── Buttons ─────────────────────────────────────────────────────────────────────────── */
  button { font: inherit; cursor: pointer; border-radius: 14px; border: 1px solid transparent; color: inherit; }
  .primary {
    background: linear-gradient(135deg, var(--cta-a), var(--cta-b));
    border-color: #ffffff2e; color: #fff; font-weight: 600; padding: 17px 18px; font-size: 16px;
    box-shadow: 0 12px 30px #2a2f6a4d;
  }
  .primary:disabled { opacity: 0.4; box-shadow: none; }
  .ghost {
    background: var(--glass); color: var(--text); border-color: var(--glass-edge); padding: 12px 15px;
    -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);
  }
  .ghost.small { padding: 8px 13px; font-size: 14px; }
  .ghost.danger { color: var(--danger); }
  .wide { width: 100%; margin-top: 22px; }
  .destination {
    width: 100%; display: flex; align-items: center; gap: 12px;
    padding: 11px 14px; text-align: left; border-radius: 16px;
  }
  .segmented { display: flex; gap: 6px; margin: 14px 0 0; }
  .segmented button {
    flex: 1; padding: 12px; background: var(--field); border: 1px solid var(--field-edge); color: var(--dim);
  }
  .segmented button.active { background: var(--accent); color: #fff; font-weight: 600; border-color: transparent; }
  .tags { display: flex; flex-wrap: wrap; gap: 6px; }
  .tags button {
    padding: 9px 14px; font-size: 14px; border-radius: 999px;
    background: var(--field); border: 1px solid var(--field-edge); color: var(--dim);
  }
  .tags button.active { background: var(--accent); color: #fff; border-color: transparent; }

  /* ── Help sheet ──────────────────────────────────────────────────────────────────────── */
  .scrim {
    position: fixed; inset: 0; z-index: 20; display: grid; align-items: end;
    background: #00000059; -webkit-backdrop-filter: blur(3px); backdrop-filter: blur(3px);
    padding: 12px; overflow-y: auto;
  }
  /* Opaque enough to read against: a sheet you have to squint through is a broken sheet. */
  .sheet { padding: 22px; border-radius: 24px; margin: auto 0 0; background: var(--sheet); }
  .sheet h2 { font-size: 19px; margin: 0 0 10px; }
  .sheet h3 { font-size: 14px; margin: 18px 0 6px; }
  .sheet p { font-size: 14.5px; line-height: 1.5; }
  .sheet strong { color: var(--text); }

  /* ── Footer: sync is the action, unpairing is a quiet way out ─────────────────────────── */
  .footer { display: grid; gap: 10px; margin-top: 30px; justify-items: center; }
  .footer .wide { margin-top: 0; }
  .status { font-size: 13px; color: var(--dim); margin: 0; text-align: center; }
  .unpair {
    background: none; border: none; padding: 2px 6px; font-size: 13px; color: var(--danger);
    text-decoration: underline; text-underline-offset: 3px;
  }

  /* ── Already in Nidus: a receipt, but one with a little weight ────────────────────────── */
  .log { padding: 4px 14px; gap: 0; }
  .log li { display: flex; align-items: center; gap: 11px; padding: 11px 0; opacity: 1; }
  .log li + li { border-top: 1px solid var(--glass-strong); }
  .log .dot { width: 6px; height: 6px; flex: none; border-radius: 50%; background: var(--accent); opacity: 0.75; }
  .logtitle { display: block; font-size: 14px; }
  .log .sub { display: block; font-size: 12px; margin-top: 2px; }

  details summary { cursor: pointer; color: var(--dim); font-size: 15px; margin-bottom: 8px; }
</style>
