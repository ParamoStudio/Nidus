# Nidus

A project incubator and orchestrator built around Markdown and small, composable tools.
Local-first. Open source. No account, no subscription, no telemetry.

Nidus is where a project lives before, during and after it is a project: a folder you own, a
workspace you arrange, and a set of tools that only ever touch what belongs to them.

It comes with three ways in, because ideas don't wait for you to be at the right screen:
the **[macOS app](#install)**, a **[Raycast extension](#capture-from-raycast)** for capturing without
leaving what you're doing, and a **[phone web app](#capture-from-your-phone)** for when you're nowhere
near the computer. All three write to the same Markdown files.

---

## The one idea

**The filesystem is the truth.** There is no database. A project is a real folder; a card is a
heading in a real `.md` file; the arrangement of your workspace is one small `nidus.json`. You can
read every byte Nidus writes in any text editor, sync it with iCloud or Git, or walk away from the
app entirely and still have your work.

Everything else follows from that:

- **Tools own their own data, never yours.** A tool writes its own `extra` fields and its own title.
  It never rewrites a card's body — so a note you wrote by hand survives a tool it was never made for.
- **Nothing happens behind your back.** No background upload, no sync service, no "smart" reorganising.
  Nidus makes exactly one network request of its own: once a day it asks GitHub whether a newer release
  exists, and tells you if so. It sends nothing, identifies nobody, and never updates itself — you get a
  link. Right-click the notice to turn the check off for good.
- **Leaving is free.** Delete the app and the folders are still folders.

## Requirements

macOS **15 Sequoia** or later. Universal binary — Apple Silicon and Intel.

On macOS 26 the interface is drawn with Liquid Glass. On Sequoia, where that doesn't exist, the same
build falls back to a translucent wash with a lit edge; the window itself stays translucent either way.
It's one download and one codebase — the check happens at runtime, so nothing is forked and there is no
"old Mac edition" to choose between.

*(Earlier releases asked for macOS 26.5, and this README claimed that couldn't be lowered without
rewriting the app. That was wrong: `glassEffect` turned out to be the only macOS 26 API in the whole
project, and it took a shim, not a rewrite.)*

## Install

1. Download the latest `Nidus-*-macOS.zip` from [Releases](https://github.com/ParamoStudio/Nidus/releases).
2. Unzip it and move **Nidus.app** to `/Applications`.
3. **The first launch needs a right-click.** Right-click (or Control-click) the app → **Open** →
   **Open** again in the dialog. After that it opens normally.

> **Why the extra step?** The app is signed ad-hoc, not with a paid Apple Developer ID, so macOS
> says it "cannot verify it is free of malware". That message means *unverified by Apple*, not
> *known to be harmful* — Apple has no opinion either way, because nobody paid for one. The source
> for exactly what you're running is in this repository; if you'd rather not take that on trust,
> build it yourself (below). This will change if the project ever gets a Developer ID.

If the right-click dance doesn't work on your machine, this does the same thing explicitly:

```bash
xattr -dr com.apple.quarantine /Applications/Nidus.app
```

## Build it yourself

```bash
git clone https://github.com/ParamoStudio/Nidus.git
```

Open `Nidus.xcodeproj` in Xcode 26 or later, pick the **Nidus** scheme, and run. No dependencies, no
package manager, no build script — it's a plain SwiftUI project.

## Keyboard

The workspace is meant to be driven without reaching for the mouse. Plain letters are shortcuts on
purpose — they only fire when nothing is focused, so they can never leak into something you're typing.

| | |
|---|---|
| `⌘E` | **Customize.** Rearrange, resize, add and remove tools; edit the project itself (name, icon, description, discipline, linked folder); and set each tool's hotkey. |
| `F` | Search this project |
| `⌘F` | Search every project |
| `Space` | Open the card the cursor is over |
| `Esc` | Close whatever is open |
| `⌘N` | New window — a fresh Greeting Panel |
| `⌘W` | Close the window |

### Tool hotkeys are yours

Each tool declares a **quick action** on a single key, and every tool on your grid can be rebound:
open Customize (`⌘E`) and set the letter you want. The defaults are:

| | |
|---|---|
| `T` | Quick Task → Task Manager |
| `I` | Quick Idea → Ideas |
| `N` | New Note → Notebook |

The binding lives on the **instance**, not the tool, so two copies of the same tool can answer to
different keys — a second Notebook for glaze tests can be `G` while the main one stays `N`. Tools you
install from a file bring their own default key, and it's rebindable exactly the same way.

Where a hotkey takes you depends on what the tool is: Task Manager and Ideas open a one-line quick-add,
Notebook drops you straight into a new note, and an installed tool opens its expanded view.

## Capture from Raycast

If you use [Raycast](https://raycast.com), Nidus comes with an extension for the other half of the
same problem: an idea arrives while you're doing something else, and you want it in the right project
without opening the app and losing your thread.

Open Raycast → **Nidus: Capture** → find the project → type. The card lands in that project's Inbox
looking exactly like one typed inside Nidus.

```text
Try more silica -- It may reduce crazing without losing too much of the matte surface
```

Everything before `--` becomes the card's title, everything after it the body. Prefix with `t- ` to
send it to the project's Task Manager instead. Projects can be given short aliases, so `gl ` jumps
straight into Glaze Lab. It finds your vault on its own; there's a preference if you keep it somewhere
unusual.

It writes to the same Markdown files the app does — no service in between, nothing to keep running.

**Installing it** ([`raycast/`](raycast/)) — it isn't on the Raycast Store yet, so this is the manual
route:

```bash
git clone https://github.com/ParamoStudio/Nidus.git
cd Nidus/raycast
npm install
npm run dev
```

Then open Raycast's **Import Extension** command and select that `raycast` folder. `npm run dev` keeps
it running with hot reload while you have the terminal open; once imported it stays in your Raycast.
Locally imported extensions are yours to manage — they don't auto-update from the Store.

## Capture from your phone

Nidus pairs with a small web app so an idea or a task can reach the right project while you're away
from the computer: **<https://paramostudio.github.io/Nidus/>**

Open Nidus → the phone button in the sidebar → scan the QR. The web app installs to your Home Screen
and works offline; captures queue on the phone and are filed into the real Inbox or Task Manager next
time Nidus is open.

It is deliberately a **capture end only** — it never shows your projects' contents. Between the two
sits a dumb mailbox (a Cloudflare Worker, [`relay/`](relay/)) that holds a few captures for a few days
and understands none of them. Nidus ships pointing at a shared relay; you can run your own in about
five minutes, and the app will verify it before accepting it.

Nothing from your vault is ever uploaded — the only thing that goes *down* to the phone is the list
of project names, so you can pick one.

## What's in here

| | |
|---|---|
| `Nidus/` | The macOS + iPadOS app (SwiftUI) |
| `raycast/` | The Raycast capture extension — [README](raycast/README.md) |
| `mobile/` | The phone capture PWA (Svelte 5) — [README](mobile/README.md) |
| `relay/` | The Cloudflare Worker mailbox — [README](relay/README.md) |
| `CHANGELOG.md` | What was built and why, stretch by stretch (in Spanish) |

## Licence

[GNU AGPL v3](LICENSE). Use it, change it, share it — and if you run a modified version as a service,
share those changes too.
