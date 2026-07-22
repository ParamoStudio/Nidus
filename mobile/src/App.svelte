<script>
  import { onMount } from "svelte";
  import {
    app, adoptFromLocation, adoptFromText, unpair, sync,
    addRecord, deleteRecord, projects, tags,
  } from "./lib/store.svelte.js";

  // The phone app pairs and captures; opened on a laptop it's a way to make a mess.
  let isDesktop = $state(false);
  let view = $state("home");        // home | compose | pending
  let project = $state(null);       // the project being captured into
  let kind = $state("inbox");       // inbox | task
  let pasteCode = $state("");
  let pasteError = $state(false);
  let query = $state("");

  // compose fields
  let title = $state("");
  let body = $state("");
  let chosenTags = $state([]);
  let dueDate = $state("");
  let dueScope = $state("day");
  let dueNote = $state("");
  let more = $state(false);

  onMount(() => {
    isDesktop = window.matchMedia("(pointer: fine) and (min-width: 900px)").matches;
    adoptFromLocation();
    sync();
    const onOnline = () => sync();
    window.addEventListener("online", onOnline);
    return () => window.removeEventListener("online", onOnline);
  });

  const visibleProjects = $derived(
    projects().filter((p) => {
      const q = query.trim().toLowerCase();
      return !q || p.name.toLowerCase().includes(q) || (p.discipline || "").toLowerCase().includes(q);
    })
  );

  function openProject(p) {
    project = p;
    kind = p.inbox ? "inbox" : "task";
    title = ""; body = ""; chosenTags = []; dueDate = ""; dueScope = "day"; dueNote = ""; more = false;
    view = "compose";
  }

  function save() {
    if (!title.trim()) return;
    const draft = {
      kind, projectID: project.id, projectName: project.name,
      title: title.trim(), body: body.trim(),
    };
    if (kind === "task") {
      if (chosenTags.length) draft.tags = chosenTags;
      if (dueDate) { draft.dueDate = new Date(dueDate + "T12:00:00").toISOString(); draft.dueScope = dueScope; }
      if (dueNote.trim()) draft.dueNote = dueNote.trim();
    }
    addRecord(draft);
    view = "home";
    sync();
  }

  function tryPaste() {
    pasteError = !adoptFromText(pasteCode);
    if (!pasteError) { pasteCode = ""; sync(); }
  }

  const toggleTag = (id) =>
    (chosenTags = chosenTags.includes(id) ? chosenTags.filter((t) => t !== id) : [...chosenTags, id]);
</script>

{#if isDesktop}
  <main class="center">
    <div class="card">
      <h1>Nidus Capture</h1>
      <p>This is the phone companion. On your computer, just use the Nidus app — it's where your projects actually live.</p>
    </div>
  </main>
{:else if !app.pairing}
  <main class="center">
    <div class="card">
      <h1>Nidus Capture</h1>
      <p>Open Nidus on your computer, click the phone button in the sidebar, and scan the QR with your camera.</p>
      <details>
        <summary>Have a pairing code?</summary>
        <p class="hint">If you added this to your Home Screen and it started unpaired, paste the code from Nidus here — iOS keeps installed apps separate from Safari.</p>
        <input bind:value={pasteCode} placeholder="NI-…" autocapitalize="off" autocorrect="off" spellcheck="false" />
        <button class="primary" onclick={tryPaste}>Pair</button>
        {#if pasteError}<p class="error">That code didn't parse. Copy it again from Nidus.</p>{/if}
      </details>
    </div>
  </main>
{:else}
  <header>
    <button class="ghost" onclick={() => (view = view === "home" ? "pending" : "home")}>
      {view === "home" ? `Waiting ${app.records.length ? `(${app.records.length})` : ""}` : "Projects"}
    </button>
    <strong>{view === "compose" ? project?.name : "Nidus"}</strong>
    <button class="ghost" onclick={sync} disabled={app.busy}>{app.busy ? "…" : "Sync"}</button>
  </header>

  {#if app.status}<p class="status">{app.status}</p>{/if}

  {#if view === "home"}
    <main>
      {#if !projects().length}
        <p class="hint">No projects yet. Open Nidus on your computer and press Sync — it publishes your project list here.</p>
      {:else}
        <input class="search" bind:value={query} placeholder="Search projects…" />
        <ul class="list">
          {#each visibleProjects as p (p.id)}
            <li><button onclick={() => openProject(p)}>
              <span class="name">{p.name}</span>
              <span class="sub">{p.discipline}</span>
            </button></li>
          {/each}
        </ul>
      {/if}
    </main>
  {:else if view === "compose"}
    <main>
      <div class="segmented">
        {#if project.inbox}
          <button class:active={kind === "inbox"} onclick={() => (kind = "inbox")}>Inbox</button>
        {/if}
        {#if project.tasks}
          <button class:active={kind === "task"} onclick={() => (kind = "task")}>Task</button>
        {/if}
      </div>

      <input class="title" bind:value={title} placeholder={kind === "task" ? "What needs doing?" : "What's on your mind?"} />
      <textarea bind:value={body} rows="4" placeholder="Notes (optional)"></textarea>

      {#if kind === "task"}
        <button class="ghost wide" onclick={() => (more = !more)}>{more ? "Fewer options" : "Tags & deadline"}</button>
        {#if more}
          {#if tags().length}
            <div class="tags">
              {#each tags() as t (t.id)}
                <button class:active={chosenTags.includes(t.id)} onclick={() => toggleTag(t.id)}>{t.name}</button>
              {/each}
            </div>
          {/if}
          <label>Deadline <input type="date" bind:value={dueDate} /></label>
          {#if dueDate}
            <div class="segmented small">
              {#each ["day", "week", "month"] as s}
                <button class:active={dueScope === s} onclick={() => (dueScope = s)}>{s}</button>
              {/each}
            </div>
            <input bind:value={dueNote} placeholder="Deadline note (optional)" />
          {/if}
        {/if}
      {/if}

      <div class="row">
        <button class="ghost" onclick={() => (view = "home")}>Cancel</button>
        <button class="primary" onclick={save} disabled={!title.trim()}>Save</button>
      </div>
    </main>
  {:else}
    <main>
      {#if !app.records.length}
        <p class="hint">Nothing waiting. Captures disappear from here once Nidus files them.</p>
      {:else}
        <ul class="list">
          {#each app.records as r (r.id)}
            <li class="record">
              <div>
                <span class="name">{r.title}</span>
                <span class="sub">{r.projectName} · {r.kind === "task" ? "Task" : "Inbox"} · {r.sent ? "waiting for Nidus" : "not sent yet"}</span>
              </div>
              <button class="ghost" onclick={() => deleteRecord(r.id)}>Delete</button>
            </li>
          {/each}
        </ul>
      {/if}
      <button class="ghost wide danger" onclick={unpair}>Unpair this phone</button>
    </main>
  {/if}
{/if}

<style>
  :global(body) {
    margin: 0; background: #12151f; color: #eef1f7;
    font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  :global(*) { box-sizing: border-box; }
  header {
    display: flex; align-items: center; justify-content: space-between; gap: 8px;
    padding: 14px 16px; position: sticky; top: 0; background: #12151fee; backdrop-filter: blur(8px);
    border-bottom: 1px solid #ffffff14;
  }
  header strong { font-weight: 600; }
  main { padding: 16px; padding-bottom: 40px; }
  main.center { min-height: 100dvh; display: grid; place-items: center; }
  .card { max-width: 420px; padding: 22px; background: #ffffff08; border: 1px solid #ffffff14; border-radius: 16px; }
  h1 { font-size: 20px; margin: 0 0 8px; }
  p { color: #aab2c5; margin: 0 0 12px; }
  .hint { font-size: 13px; color: #8c94a8; }
  .error { color: #ff8080; font-size: 13px; }
  .status { margin: 0; padding: 8px 16px; font-size: 13px; color: #8c94a8; }
  input, textarea {
    width: 100%; padding: 12px; margin: 6px 0 12px; font: inherit; color: inherit;
    background: #ffffff0d; border: 1px solid #ffffff1f; border-radius: 12px;
  }
  input.title { font-size: 17px; }
  input:focus, textarea:focus { outline: 2px solid #ff8a3d66; border-color: #ff8a3d; }
  button { font: inherit; cursor: pointer; border-radius: 12px; border: 1px solid transparent; }
  .primary { background: #ff8a3d; color: #1b1205; font-weight: 600; padding: 12px 18px; }
  .primary:disabled { opacity: 0.45; }
  .ghost { background: #ffffff0d; color: #dfe4ef; border-color: #ffffff1f; padding: 9px 14px; }
  .ghost.wide { width: 100%; margin-top: 10px; }
  .ghost.danger { color: #ff9a9a; }
  .row { display: flex; gap: 10px; justify-content: flex-end; margin-top: 8px; }
  .list { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  .list button, .record {
    width: 100%; text-align: left; padding: 14px; background: #ffffff0a;
    border: 1px solid #ffffff14; border-radius: 14px; color: inherit;
  }
  .record { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
  .name { display: block; font-weight: 600; }
  .sub { display: block; font-size: 12px; color: #8c94a8; margin-top: 2px; }
  .segmented { display: flex; gap: 6px; margin-bottom: 12px; }
  .segmented button {
    flex: 1; padding: 10px; background: #ffffff0d; border: 1px solid #ffffff1f; color: #cfd6e6;
  }
  .segmented button.active { background: #ff8a3d; color: #1b1205; font-weight: 600; border-color: #ff8a3d; }
  .segmented.small button { padding: 7px; font-size: 13px; text-transform: capitalize; }
  .tags { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px; }
  .tags button { padding: 7px 12px; font-size: 13px; background: #ffffff0d; border: 1px solid #ffffff1f; color: #cfd6e6; }
  .tags button.active { background: #ff8a3d; color: #1b1205; border-color: #ff8a3d; }
  label { display: block; font-size: 13px; color: #aab2c5; }
  details summary { cursor: pointer; color: #aab2c5; font-size: 14px; margin-bottom: 8px; }
  .search { margin-bottom: 12px; }
</style>
