# Nidus Capture (the phone app)

A small installable web app that lets you drop ideas and tasks into a Nidus project while you're away
from your computer. Nidus files them into the real `.md` files the next time you open it.

It is **not** a second Nidus. It captures; the computer does the work.

## How it fits together

```
   Nidus (Mac/iPad)              relay (your Cloudflare Worker)             this app (phone)
   ─────────────────             ────────────────────────────              ─────────────────
   pushes project list  ──────▶  down:<token>   ──────────────────────▶  cached, so composing
   files captures       ◀──────  up:<token>     ◀──────────────────────  works offline
   deletes what it filed ─────▶
```

Nidus is the source of truth. The relay is a dumb mailbox that forgets everything after 7 days
(see [`../relay/README.md`](../relay/README.md)). No accounts, nothing to run.

## Pairing

In Nidus: **sidebar → the phone button** (next to `?`). Scan the QR with your camera, then add the page
to your Home Screen.

The QR carries the pairing **and** the relay address, so switching relays just means re-scanning —
nothing is ever typed on the phone.

> **On iOS, a Home-Screen web app gets its own storage container, separate from Safari.** A pairing made
> in Safari is invisible to the installed app, which starts up unpaired. That's why the panel in Nidus
> also shows a **pairing code**: install first, then paste the code into the installed app.

## What it does

- Lists your **active** projects (name + discipline), searchable.
- Captures into a project's **Inbox** or its **Task Manager**.
- A task can optionally carry notes, tags (from your vault's tag bank) and a deadline with Nidus's own
  day/week/month scope.
- Works **offline**: captures queue on the phone and go out when there's a network.
- A capture disappears from the phone only once Nidus has actually filed it — never on the strength of
  "we uploaded it".

## Development

```sh
npm install
npm run dev       # local, relative base
npm test          # the pairing-code codec is pure and tested
npm run build     # production; CI sets PAGES_BASE=/Nidus/
```

`PAGES_BASE` is **not** cosmetic. On a GitHub Pages project site the app is served from `/<repo>/`; with
a relative base the service worker gets an invalid scope, and the app installs but never works offline —
while looking perfectly fine on the first visit. CI sets it; local `vite preview` keeps the relative one.

Deploy is automatic: pushing changes under `mobile/` runs
[`deploy-mobile.yml`](../.github/workflows/deploy-mobile.yml). Repo settings → Pages must be set to
**GitHub Actions**.

## Limits worth knowing

- A record left uncollected dies in the relay after **7 days**, and the phone drops its copy once Nidus
  confirms it. Past that window there is no copy anywhere.
- Up to 50 pending records **per pairing** (shared by every phone on it).
- The pairing token is a bearer credential delivered by QR. Anyone holding it can read and write that
  channel. Fine for "buy more kaolin"; not for credentials, health data, or money.
