# The Nidus phone relay

A tiny Cloudflare Worker that lets your phone hand captures to Nidus when the computer isn't around.

It is **a mailbox, not a server**. It stores two opaque blobs per pairing and forgets them after 7 days.
It has no accounts, no database you manage, and no idea what any of the data means — every rule about
what it means lives in Nidus and in the phone web app. Your vault stays local; only what you capture on
the phone passes through, briefly.

## Why this exists

The phone can't talk to your Mac directly: the Mac may be off, on another network, or in another
building. And a web app can only work **offline** (which is the whole point — capturing in a workshop
with no signal) if it's served over HTTPS, which rules out the Mac serving it over the LAN. So a small
public mailbox in the middle is the only shape that satisfies both.

## The contract

Base URL: `https://<your-worker>.workers.dev`

| Method | Path | Who | Meaning |
|---|---|---|---|
| `PUT` | `/channel/:token/down` | Nidus | Overwrite the reference payload (your projects + tags) |
| `GET` | `/channel/:token/down` | phone | Read it (`null` if never written) |
| `POST` | `/channel/:token/up` | phone | Append/replace one captured record, keyed by its `id` |
| `GET` | `/channel/:token/up` | Nidus | Read everything waiting |
| `DELETE` | `/channel/:token/up?id=…` | Nidus | Confirm one record consumed |
| `DELETE` | `/channel/:token/up` | Nidus | Clear the box |

KV keys are `down:<token>` and `up:<token>` — the mailbox is keyed by **pairing**, not by device. Two
vaults never share a queue, and several phones can share one pairing (they all post to the same box).

Limits: 7-day TTL on every write, `MAX_PENDING` 50 records **per pairing**, `MAX_BODY_BYTES` 512 KB,
tokens must match `^[A-Za-z0-9_-]{16,64}$`. CORS is `*` because the phone app is served from a different
origin (GitHub Pages) than the worker.

## Setting up your own (10 minutes, free)

You need a free Cloudflare account. No domain, no card.

**Dashboard route (no tooling):**

1. **Storage & Databases → KV → Create instance.** Name it `NIDUS_RELAY`.
2. **Compute → Workers → Create → Hello World**, deploy it, then **Edit code**: delete everything and
   paste the contents of [`worker.js`](worker.js). Deploy.
3. **Settings → Bindings → Add → KV namespace.** Variable name `NIDUS_RELAY`, pointing at the namespace
   from step 1. Save and deploy.
4. Copy the Worker's URL. In Nidus, open the phone panel → **Advanced** → paste it. Nidus verifies it by
   writing a probe and reading it back before accepting.

**Wrangler route:**

```sh
npm install -g wrangler
wrangler login
wrangler kv namespace create NIDUS_RELAY   # paste the printed id into wrangler.toml
cd relay && wrangler deploy                # prints your Worker URL
```

> **Paste _this_ worker.** Asking an AI for "a Cloudflare KV worker" gets you a generic key-value store
> that looks right and has none of the channel routes, no CORS and no expiry. It fails confusingly.

Free-tier reality: KV allows roughly 1,000 writes/day. A busy pairing does maybe 10–20, so one free
worker comfortably serves you and anyone you share it with.

## Testing it

```sh
T=abcdefghijklmnop1234
curl -X PUT  "$BASE/channel/$T/down" -d '{"hello":"world"}'
curl         "$BASE/channel/$T/down"            # → {"hello":"world"}
curl -X POST "$BASE/channel/$T/up"   -d '{"id":"r1","title":"one"}'
curl         "$BASE/channel/$T/up"              # → [{"id":"r1",...}]
curl -X DELETE "$BASE/channel/$T/up?id=r1"
curl         "$BASE/channel/$T/up"              # → []
```

## The security model, honestly

The pairing token is a **bearer credential** delivered by QR and never typed. Anyone holding it can read
and write that channel. There is no per-request auth, no encryption beyond TLS, no audit trail. That is
proportionate for short-lived operational captures — a note to yourself, a task title.

It is **not** proportionate for credentials, health data, money, or anything you'd have to notify a
regulator about. Don't capture those on the phone side.

Also know the shape of the data loss risk: a record sent from the phone dies in the relay after 7 days,
and the phone drops its own copy once Nidus confirms it. Past that window, there is no copy anywhere.
