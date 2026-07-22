<script>
  /**
   * Nidus's own deadline picker — deliberately NOT the phone's native date input.
   *
   * A Nidus deadline isn't a date, it's a date plus how strict it is: a hard day, a soft week, or a
   * whole month. The native picker can only ever say "day", so using it would quietly throw away two
   * thirds of the feature. Here the scope comes from the gesture:
   *
   *   tap a day          → that day
   *   tap it again       → widen to its week
   *   tap the month name → the whole month
   *
   * Folded away until you need it: most captures have no deadline at all.
   */
  let { date = $bindable(""), scope = $bindable("day") } = $props();

  const DAY_MS = 86400000;
  const WEEKDAYS = ["M", "T", "W", "T", "F", "S", "S"];
  const MONTHS = ["January", "February", "March", "April", "May", "June",
                  "July", "August", "September", "October", "November", "December"];

  let open = $state(false);
  let lastTap = { iso: "", at: 0 };

  const parse = (iso) => {
    const [y, m, d] = (iso || "").split("-").map(Number);
    return iso ? new Date(y, m - 1, d) : null;
  };
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  /** Monday-start, matching the app's ISO week (Calendar.startOfWeek). */
  const startOfWeek = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate() - ((d.getDay() + 6) % 7));

  const today = new Date();
  const selected = $derived(parse(date));
  // The month on screen follows the selection, but you can page away from it freely.
  let cursor = $state(null);
  const view = $derived(cursor ?? selected ?? today);

  /** Six weeks of cells, Monday-start, so the grid never jumps height between months. */
  const cells = $derived.by(() => {
    const first = new Date(view.getFullYear(), view.getMonth(), 1);
    const start = startOfWeek(first);
    return Array.from({ length: 42 }, (_, i) => new Date(start.getTime() + i * DAY_MS));
  });

  const sameDay = (a, b) => a && b && iso(a) === iso(b);
  const inMonth = (d) => d.getMonth() === view.getMonth();

  function isSelected(d) {
    if (!selected) return false;
    if (scope === "day") return sameDay(d, selected);
    if (scope === "week") return sameDay(startOfWeek(d), startOfWeek(selected));
    return d.getMonth() === selected.getMonth() && d.getFullYear() === selected.getFullYear();
  }

  /** First tap sets the day; a second tap on the same day widens it to that whole week. */
  function tapDay(d) {
    const key = iso(d);
    const now = Date.now();
    const again = key === lastTap.iso && now - lastTap.at < 500;
    lastTap = { iso: key, at: now };
    date = key;
    scope = again && scope === "day" ? "week" : "day";
    cursor = d;
  }

  function tapMonth() {
    date = iso(new Date(view.getFullYear(), view.getMonth(), 1));
    scope = "month";
  }

  function page(delta) {
    cursor = new Date(view.getFullYear(), view.getMonth() + delta, 1);
  }

  function clear() {
    date = "";
    scope = "day";
    lastTap = { iso: "", at: 0 };
  }

  /** The same wording the app puts on a task's deadline pill. */
  const summary = $derived.by(() => {
    if (!selected) return "No deadline";
    if (scope === "month") return MONTHS[selected.getMonth()];
    const label = `${MONTHS[selected.getMonth()].slice(0, 3)} ${selected.getDate()}`;
    if (scope === "week") {
      const s = startOfWeek(selected);
      return `Wk ${MONTHS[s.getMonth()].slice(0, 3)} ${s.getDate()}`;
    }
    return label;
  });
</script>

<button class="field" class:set={!!selected} onclick={() => (open = !open)}>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round">
    <rect x="3.6" y="5.2" width="16.8" height="15.2" rx="3" />
    <path d="M3.6 9.8h16.8M8.4 3.6v3.2M15.6 3.6v3.2" />
  </svg>
  <span class="grow">{summary}</span>
  <span class="chev">{open ? "⌄" : "›"}</span>
</button>

{#if open}
  <div class="cal">
    <div class="calhead">
      <button class="nav" onclick={() => page(-1)} aria-label="Previous month">‹</button>
      <!-- Tapping the month name IS the "whole month" scope — the gesture is the control. -->
      <button class="month" class:active={scope === "month" && selected && selected.getMonth() === view.getMonth()} onclick={tapMonth}>
        {MONTHS[view.getMonth()]} {view.getFullYear()}
      </button>
      <button class="nav" onclick={() => page(1)} aria-label="Next month">›</button>
    </div>

    <div class="grid dow">
      {#each WEEKDAYS as d}<span class="dowcell" aria-hidden="true">{d}</span>{/each}
    </div>
    <div class="grid">
      {#each cells as d (d.getTime())}
        <button
          class="day"
          class:muted={!inMonth(d)}
          class:today={sameDay(d, today)}
          class:on={isSelected(d)}
          class:wide={isSelected(d) && scope !== "day"}
          onclick={() => tapDay(d)}
        >{d.getDate()}</button>
      {/each}
    </div>

    <p class="hint">Tap a day · tap it again for its week · tap the month for all of it.</p>
    <div class="calfoot">
      <span class="scope">{scope === "day" ? "Hard date" : scope === "week" ? "Some time that week" : "Some time that month"}</span>
      {#if selected}<button class="clear" onclick={clear}>Clear</button>{/if}
    </div>
  </div>
{/if}

<style>
  .field {
    width: 100%; display: flex; align-items: center; gap: 11px; padding: 14px; text-align: left;
    background: var(--field); border: 1px solid var(--field-edge); border-radius: 14px; color: var(--dim);
    -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);
  }
  .field.set { color: var(--text); }
  .field svg { width: 19px; height: 19px; flex: none; color: var(--dim); }
  .grow { flex: 1; min-width: 0; }
  .chev { color: var(--dim); font-size: 18px; }

  .cal {
    margin-top: 8px; padding: 12px; border-radius: 18px;
    background: var(--glass); border: 1px solid var(--glass-edge);
    -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px);
  }
  .calhead { display: flex; align-items: center; gap: 6px; margin-bottom: 8px; }
  .nav {
    width: 34px; height: 34px; flex: none; border-radius: 50%; font-size: 17px;
    background: none; border: 1px solid var(--field-edge); color: var(--dim);
  }
  .month {
    flex: 1; padding: 8px; font-size: 15px; font-weight: 600; background: none; border: 1px solid transparent;
  }
  .month.active { background: var(--accent); color: #fff; border-color: transparent; }

  .grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 2px; }
  .dow { margin-bottom: 2px; }
  .dowcell {
    text-align: center; font-size: 10.5px; letter-spacing: 0.6px; text-transform: uppercase;
    color: var(--dim); padding: 2px 0;
  }
  .day {
    aspect-ratio: 1; display: grid; place-items: center; font-size: 14px;
    background: none; border: 1px solid transparent; border-radius: 11px; color: var(--text);
  }
  .day.muted { color: var(--dim); opacity: 0.45; }
  .day.today { border-color: var(--field-edge); font-weight: 600; }
  .day.on { background: var(--accent); color: #fff; font-weight: 600; }
  /* A week or a month is a WINDOW, not a date: it reads softer than a hard day. */
  .day.wide { background: var(--accent-soft); color: var(--text); font-weight: 500; }

  .hint { font-size: 11.5px; color: var(--dim); margin: 10px 0 0; line-height: 1.35; }
  .calfoot { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-top: 6px; }
  .scope { font-size: 12px; color: var(--accent); font-weight: 600; }
  .clear { background: none; border: none; color: var(--dim); font-size: 13px; padding: 4px; }
</style>
