# Nidus for Raycast

Capture a thought in the Inbox of a Nidus project without opening the app.

## Capture

1. Run **Nidus: Capture**.
2. Find a project by its name, discipline, or alias.
3. Press Enter to enter the project.
4. Type a title, optionally followed by ` -- ` and a note.
5. Press Enter. The card is written to that project's Inbox and Raycast closes.

Example:

```text
Try more silica -- It may reduce crazing without losing too much of the matte surface
```

The text before `--` becomes the card title. The text after it becomes the Markdown body. A space
after the separator is optional: both `Title -- note` and `Title --note` work.

### Tasks

Start a capture with `t- ` to send it directly to the project's primary Task Manager:

```text
t- Buy more clay -- Ask whether the red stoneware is back in stock
```

The task is created without a date or tags. Those can be added later in Nidus. `t-` acts as a route
as soon as it appears at the very start; the following space is optional.

The destination selector next to the search bar offers the same Inbox/Task choice without syntax.
It is the guided path for new users; both paths write the exact same card format.

## Aliases

Use **Manage Project Aliases**, or the **Set Aliases** action on any project. Typing an exact alias
followed by a space enters that project immediately.

Aliases live in `_routing/project-aliases.json` inside the vault. They are deliberately readable by
future Nidus automations, including the planned classifier for `_inbox-global/`.

## Vault discovery

The extension resolves the vault in this order:

1. The optional **Vault Path** extension preference.
2. `~/Library/Application Support/Nidus/vault-path.txt`, written by the Nidus app.

Open Nidus once if the sidecar does not exist yet.

## Development

```sh
npm install
npm run dev
```

`Project Overview` is intentionally deferred. The first release stays focused on the low-friction
project → capture → Inbox path.

## Install

Not on the Raycast Store yet, so it's the manual route:

```bash
npm install
npm run dev
```

Then run Raycast's **Import Extension** command and pick this folder. Locally imported extensions are
yours to manage — they don't auto-update from the Store.

## Licence

[GNU AGPL v3](../LICENSE), the same as the rest of Nidus.
