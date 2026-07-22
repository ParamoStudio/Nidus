/**
 * The phone half: pairing, the local queue, and the sync round trip.
 *
 * Everything is local-first. You compose captures offline; they sit in localStorage until there's a
 * network. A record is dropped from the phone ONLY once Nidus has filed it and it has disappeared from
 * the relay — never on the strength of "we uploaded it".
 */

import { parsePairHash, decodePairInput } from "./paircode.js";

const LS = {
  pairing: "nidus.pairing",
  reference: "nidus.reference",
  records: "nidus.records",
  recent: "nidus.recentProjects",
  history: "nidus.history",
};

function load(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}
function save(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {}
}

export const app = $state({
  pairing: load(LS.pairing, null), // { token, base }
  reference: load(LS.reference, null), // { projects, tags, pushedAt }
  records: load(LS.records, []), // local queue, still to be collected
  recent: load(LS.recent, []), // project ids, most recently captured-into first
  history: load(LS.history, []), // the last few captures Nidus has already filed
  status: "",
  busy: false,
});

const persistRecords = () => save(LS.records, app.records);
// Kept generous on purpose: this is the only place you can see what the phone has already handed over,
// and watching entries vanish after a few captures reads as data loss.
const HISTORY_MAX = 30;

/** The project a new capture defaults to: whatever you used last, if it still exists. */
export function defaultProject() {
  const all = projects();
  return all.find((p) => p.id === app.recent[0]) || all[0] || null;
}

export function noteProjectUsed(id) {
  app.recent = [id, ...app.recent.filter((x) => x !== id)].slice(0, 8);
  save(LS.recent, app.recent);
}

/** Projects split the way the capture flow wants them: pinned, recently used, then the rest. */
export function groupedProjects() {
  const all = projects();
  const pinned = all.filter((p) => p.pinned);
  const recent = app.recent.map((id) => all.find((p) => p.id === id)).filter((p) => p && !p.pinned);
  const rest = all.filter((p) => !p.pinned && !recent.includes(p));
  return { pinned, recent, rest };
}

// ---- pairing ------------------------------------------------------------------------------------

/** A new token means a DIFFERENT computer — never mix two vaults' reference data. */
export function adoptPairing(pairing) {
  if (!pairing?.token) return false;
  const changed = app.pairing?.token !== pairing.token;
  app.pairing = pairing;
  save(LS.pairing, pairing);
  if (changed) {
    app.reference = null;
    app.records = [];
    save(LS.reference, null);
    persistRecords();
  }
  return true;
}

export function adoptFromText(text) {
  const parsed = decodePairInput(text);
  return parsed ? adoptPairing(parsed) : false;
}

/** Reads `#pair=…` from the QR, adopts it, then strips the hash so a refresh doesn't re-parse it. */
export function adoptFromLocation() {
  const parsed = parsePairHash(location.hash);
  if (!parsed) return false;
  const ok = adoptPairing(parsed);
  history.replaceState(null, "", location.pathname + location.search);
  return ok;
}

export function unpair() {
  app.pairing = null;
  app.reference = null;
  app.records = [];
  save(LS.pairing, null);
  save(LS.reference, null);
  persistRecords();
}

// ---- records ------------------------------------------------------------------------------------

/** Timestamp + randomness: a bare counter collides when two phones capture in the same millisecond,
 *  and the relay de-duplicates by id — one of them would silently vanish. */
function newID() {
  const rand = (crypto.randomUUID?.() || Math.random().toString(36)).replace(/-/g, "").slice(0, 10);
  return `${Date.now().toString(36)}-${rand}`;
}

export function addRecord(draft) {
  const record = { ...draft, id: newID(), createdAt: new Date().toISOString(), sent: false };
  app.records = [record, ...app.records];
  persistRecords();
  return record;
}

export function updateRecord(id, patch) {
  app.records = app.records.map((r) => (r.id === id ? { ...r, ...patch, sent: false } : r));
  persistRecords();
}

export function deleteRecord(id) {
  app.records = app.records.filter((r) => r.id !== id);
  persistRecords();
}

// ---- relay --------------------------------------------------------------------------------------

const trimBase = (b) => (b || "").replace(/\/+$/, "");
const channel = (suffix) => `${trimBase(app.pairing.base)}/channel/${app.pairing.token}/${suffix}`;

async function relay(method, suffix, body) {
  const res = await fetch(channel(suffix), {
    method,
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const err = new Error(`relay ${res.status}`);
    err.status = res.status; // callers need to tell "mailbox full" from "network died"
    throw err;
  }
  return res.json();
}

/** What actually crosses the wire — the local bookkeeping fields stay on the phone. */
function payload(record) {
  const { sent, projectName, ...rest } = record;
  return rest;
}

export async function sync() {
  if (!app.pairing?.base || app.busy) return;
  if (!navigator.onLine) {
    app.status = "Offline — will sync when you're back.";
    return;
  }
  app.busy = true;
  try {
    // 1. Push anything the relay hasn't accepted yet (re-posting an edited record replaces it by id).
    let held = 0;
    for (const record of app.records.filter((r) => !r.sent)) {
      try {
        await relay("POST", "up", payload(record));
        record.sent = true;
      } catch (e) {
        // The mailbox is full: not an error, just back-pressure. Keep the rest here — they'll go out
        // once Nidus collects — rather than hammering the relay or losing anything.
        if (e.status === 409) { held = app.records.filter((r) => !r.sent).length; break; }
        throw e;
      }
    }
    persistRecords();

    // 2. Refresh the project/tag list so composing works offline next time.
    const down = await relay("GET", "down");
    if (down) {
      app.reference = down;
      save(LS.reference, down);
    }

    // 3. The confirmation round trip: anything we sent that is no longer waiting was filed by Nidus.
    const pending = (await relay("GET", "up")) || [];
    const stillWaiting = new Set(pending.map((p) => p.id));
    const collected = app.records.filter((r) => r.sent && !stillWaiting.has(r.id));
    if (collected.length) {
      app.records = app.records.filter((r) => !(r.sent && !stillWaiting.has(r.id)));
      persistRecords();
      // Keep a short local trail of what Nidus took, so the landing screen can show recent activity.
      app.history = [...collected.map((r) => ({ ...r, filedAt: new Date().toISOString() })), ...app.history]
        .slice(0, HISTORY_MAX);
      save(LS.history, app.history);
    }

    const waiting = app.records.length;
    app.status = held
      ? `Nidus has a full inbox — ${held} kept on this phone until you collect them.`
      : collected.length
        ? `${collected.length} filed in Nidus.${waiting ? ` ${waiting} still waiting.` : ""}`
        : waiting
          ? `${waiting} waiting for Nidus.`
          : "Everything's synced.";
  } catch {
    app.status = "Couldn't reach the relay.";
  }
  app.busy = false;
}

export const projects = () => app.reference?.projects ?? [];
export const userName = () => app.reference?.userName || "";
export const tags = () => app.reference?.tags ?? [];
