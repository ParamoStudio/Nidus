/**
 * Nidus phone relay — a deliberately stupid mailbox.
 *
 * It stores exactly two opaque blobs per pairing and forgets them after a week. It has no idea what
 * any of it means: no accounts, no validation of Nidus's domain objects, no merging. Every rule about
 * what the data means lives in the Nidus app and the phone web app. That is what keeps this ~130 lines
 * and lets one free Worker serve everybody.
 *
 *   PUT    /channel/:token/down      (desktop) overwrite the reference payload (projects + tags)
 *   GET    /channel/:token/down      (phone)   read it — `null` if never written
 *   POST   /channel/:token/up        (phone)   append/replace ONE record, keyed by its `id`
 *   GET    /channel/:token/up        (desktop) read all pending records
 *   DELETE /channel/:token/up?id=…   (desktop) confirm one consumed
 *   DELETE /channel/:token/up        (desktop) clear the whole box
 *
 * KV keys are `down:<token>` and `up:<token>` — the mailbox is keyed by PAIRING, not by device. Two
 * vaults never share a queue, and any number of phones can share one pairing.
 *
 * Paste this file as-is into the Cloudflare dashboard editor (Workers → Edit code), or deploy it with
 * wrangler. Bind a KV namespace to the variable name NIDUS_RELAY.
 */

const TOKEN_RE = /^[A-Za-z0-9_-]{16,64}$/;
const TTL_SECONDS = 60 * 60 * 24 * 7; // 7 days — a backstop so abandoned channels disappear
const MAX_PENDING = 50;               // per PAIRING (shared by every phone on it), not per device
const MAX_BODY_BYTES = 512 * 1024;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,PUT,POST,DELETE,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

async function readBody(request) {
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return { error: json({ error: "too_large" }, 413) };
  try {
    return { value: raw ? JSON.parse(raw) : null };
  } catch {
    return { error: json({ error: "bad_json" }, 400) };
  }
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean); // ["channel", token, "down"|"up"]

    if (parts.length !== 3 || parts[0] !== "channel") {
      return json({ error: "not_found", hint: "/channel/:token/down|up" }, 404);
    }
    const [, token, box] = parts;

    // Validate BEFORE touching KV, so a malformed path can never create junk keys.
    if (!TOKEN_RE.test(token)) return json({ error: "bad_token" }, 400);
    if (box !== "down" && box !== "up") return json({ error: "not_found" }, 404);
    if (!env.NIDUS_RELAY) return json({ error: "kv_not_bound", hint: "Bind a KV namespace named NIDUS_RELAY" }, 500);

    const key = `${box}:${token}`;

    // ---- down: the desktop's reference payload (projects + tags) ------------------------------
    if (box === "down") {
      if (request.method === "PUT") {
        const { value, error } = await readBody(request);
        if (error) return error;
        await env.NIDUS_RELAY.put(key, JSON.stringify(value), { expirationTtl: TTL_SECONDS });
        return json({ ok: true });
      }
      if (request.method === "GET") {
        const stored = await env.NIDUS_RELAY.get(key);
        return json(stored ? JSON.parse(stored) : null);
      }
      return json({ error: "method_not_allowed" }, 405);
    }

    // ---- up: records the phone captured, waiting for the desktop ------------------------------
    const stored = await env.NIDUS_RELAY.get(key);
    const list = stored ? JSON.parse(stored) : [];

    if (request.method === "GET") return json(list);

    if (request.method === "POST") {
      const { value, error } = await readBody(request);
      if (error) return error;
      if (!value || typeof value !== "object" || typeof value.id !== "string" || !value.id) {
        return json({ error: "missing_id" }, 400);
      }
      // Replace by id, so editing a record on the phone and re-syncing UPDATES instead of duplicating.
      const next = [...list.filter((x) => x && x.id !== value.id), value];
      if (next.length > MAX_PENDING) return json({ error: "too_many_pending", max: MAX_PENDING }, 409);
      await env.NIDUS_RELAY.put(key, JSON.stringify(next), { expirationTtl: TTL_SECONDS });
      return json({ ok: true, pending: next.length });
    }

    if (request.method === "DELETE") {
      const id = url.searchParams.get("id");
      if (!id) {
        await env.NIDUS_RELAY.delete(key);
        return json({ ok: true, pending: 0 });
      }
      const next = list.filter((x) => x && x.id !== id);
      if (next.length === 0) await env.NIDUS_RELAY.delete(key);
      else await env.NIDUS_RELAY.put(key, JSON.stringify(next), { expirationTtl: TTL_SECONDS });
      return json({ ok: true, pending: next.length });
    }

    return json({ error: "method_not_allowed" }, 405);
  },
};
