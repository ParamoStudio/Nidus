//
//  InstalledTool.swift
//  Nidus
//
//  The runtime host for INSTALLABLE tools (see NIDUS-installable-tool-spec.md): a user-imported `.js`
//  that adds a whole tool — tile, cards, expanded view — without any native code. The `.js` declares a
//  `manifest` plus render functions (`tile`/`expanded`/`card`) that return declarative view TREES, and
//  `handlers` that mutate data. This file parses the manifest, and runs the JS in a bare
//  JavaScriptCore context with an injected `nidus` object bridged to the instance's cards (via
//  CardStore). The declarative trees are painted natively by `InstalledToolViews.swift`.
//

import SwiftUI
import JavaScriptCore

// MARK: - Manifest + model

struct InstalledToolManifest: Equatable {
    let id: String
    let name: String
    let icon: String
    let summary: String
    let version: String
    let sizes: [ToolSize]
    let allowsMultiple: Bool
    let store: [String]          // the tool's own `.md` file(s)
    let shareable: Bool
    let accepts: [CardKind]
    let produces: CardKind
    let hotkey: String?          // optional single letter → its quick action opens the expanded view
    let openLabel: String?       // label for the tile's pinned "open expanded" footer (else "Open <name>")
}

/// An installed tool: its manifest + the source `.js` (evaluated on demand).
struct InstalledTool: Identifiable, Equatable {
    let manifest: InstalledToolManifest
    let source: String
    let sourceURL: URL
    var id: String { manifest.id }
    static func == (a: InstalledTool, b: InstalledTool) -> Bool {
        a.sourceURL == b.sourceURL && a.manifest == b.manifest
    }
}

// MARK: - Engine (JavaScriptCore + the `nidus` bridge)

enum InstalledToolEngine {

    /// Parses a `.js` into an InstalledTool by reading its `tool.manifest`. nil if it isn't valid.
    static func load(_ url: URL) -> InstalledTool? {
        guard let source = try? String(contentsOf: url, encoding: .utf8),
              let ctx = JSContext() else { return nil }
        ctx.evaluateScript(source)
        guard let tool = ctx.objectForKeyedSubscript("tool"), !tool.isUndefined,
              let m = tool.objectForKeyedSubscript("manifest"), !m.isUndefined,
              let dict = m.toDictionary() as? [String: Any] else { return nil }
        guard let id = dict["id"] as? String, let name = dict["name"] as? String else { return nil }

        let sizes = (dict["sizes"] as? [String] ?? []).compactMap { ToolSize(rawValue: $0) }
        let manifest = InstalledToolManifest(
            id: id, name: name,
            icon: (dict["icon"] as? String) ?? "square.grid.2x2",
            summary: (dict["summary"] as? String) ?? "",
            version: (dict["version"] as? String) ?? "1.0.0",
            sizes: sizes.isEmpty ? [.small, .medium] : sizes,
            allowsMultiple: (dict["allowsMultiple"] as? Bool) ?? true,
            store: (dict["store"] as? [String] ?? []).filter { $0.hasSuffix(".md") },
            shareable: (dict["shareable"] as? Bool) ?? false,
            accepts: (dict["accepts"] as? [String] ?? ["generic"]).compactMap { CardKind(rawValue: $0) },
            produces: CardKind(rawValue: (dict["produces"] as? String) ?? "generic") ?? .generic,
            hotkey: (dict["hotkey"] as? String).flatMap { $0.first.map(String.init) },
            openLabel: dict["openLabel"] as? String)
        return InstalledTool(manifest: manifest, source: source, sourceURL: url)
    }

    /// Parameters for one render/handler run (which instance's file, its size, and app hooks).
    struct Run {
        let tool: InstalledTool
        let primaryFile: URL?         // the resolved `.md` for THIS instance (store[0])
        let size: String
        var vaultURL: URL?            // vault root → the cross-project bank lives at <vault>/_library/
        var onOpenCard: (String) -> Void = { _ in }
        var onOpenExpanded: () -> Void = {}
    }

    /// Whether the tool defines a given function (e.g. a custom `card` detail view).
    static func defines(_ tool: InstalledTool, _ fn: String) -> Bool {
        guard let ctx = JSContext() else { return false }
        ctx.evaluateScript(tool.source)
        guard let t = ctx.objectForKeyedSubscript("tool"), !t.isUndefined,
              let f = t.objectForKeyedSubscript(fn) else { return false }
        return !f.isUndefined && !f.isNull
    }

    /// Runs a render function (`tile`/`expanded`/`card`) and returns the view tree (a dict or array).
    static func render(_ fn: String, _ run: Run, card: [String: Any]? = nil) -> Any? {
        guard let (ctx, tool, ctxObj) = context(run) else { return nil }
        guard let f = tool.objectForKeyedSubscript(fn), !f.isUndefined, !f.isNull else { return nil }
        // Pass the card as the first arg for any card-scoped render (`card` AND `edit`); the tool's
        // edit form pre-fills from it — without this it opened blank.
        let args: [Any] = (card != nil) ? [card!, ctxObj] : [ctxObj]
        let result = f.call(withArguments: args)
        _ = ctx   // keep alive through the call
        return result?.toObject()
    }

    /// Runs a named handler with a payload (a form's data or a tapped card's id). Handlers mutate via
    /// `nidus`; the caller re-renders afterward.
    static func runHandler(_ name: String, payload: [String: Any], _ run: Run) {
        guard let (ctx, tool, ctxObj) = context(run) else { return }
        guard let handlers = tool.objectForKeyedSubscript("handlers"), !handlers.isUndefined,
              let h = handlers.objectForKeyedSubscript(name), !h.isUndefined, !h.isNull else { return }
        _ = h.call(withArguments: [ctxObj, payload])
        _ = ctx
    }

    // MARK: nidus bridge

    /// Builds a JSContext with the tool source + a `nidus` object bound to the instance's file, and a
    /// `ctx` argument object (`{ nidus, size, cards }`). Returns (context, tool JSValue, ctx JSValue).
    private static func context(_ run: Run) -> (JSContext, JSValue, JSValue)? {
        guard let ctx = JSContext() else { return nil }
        ctx.exceptionHandler = { _, exc in
            print("[InstalledTool] \(run.tool.id) JS error: \(exc?.toString() ?? "?")")
        }
        ctx.evaluateScript(run.tool.source)
        guard let tool = ctx.objectForKeyedSubscript("tool"), !tool.isUndefined else { return nil }

        let file = run.primaryFile
        let origin = run.tool.id
        let onOpen = run.onOpenCard

        func readCards() -> [Card] { file.map { CardStore.read(from: $0) } ?? [] }

        let all: @convention(block) () -> [[String: Any]] = { readCards().map(cardToDict) }
        let get: @convention(block) (String) -> Any = { id in
            readCards().first { $0.id == id }.map(cardToDict) ?? NSNull()
        }
        let add: @convention(block) ([String: Any]) -> [String: Any] = { d in
            let card = cardFromDict(d, origin: origin)
            if let file { CardStore.append(card, to: file) }
            return cardToDict(card)
        }
        let update: @convention(block) (String, [String: Any]) -> Void = { id, patch in
            guard let file, var c = CardStore.read(from: file).first(where: { $0.id == id }) else { return }
            if let t = patch["title"] as? String { c.title = t }
            if let b = patch["body"] as? String { c.body = b }
            if let imgs = patch["images"] as? [String] { c.images = imgs }
            if let e = patch["extra"] as? [String: Any] { for (k, v) in e { c.extra[k] = "\(v)" } }
            CardStore.update(c, in: file)
        }
        let remove: @convention(block) (String) -> Void = { id in
            if let file { CardStore.remove(id: id, from: file) }
        }
        let openCard: @convention(block) (String) -> Void = { id in
            DispatchQueue.main.async { onOpen(id) }
        }
        let onExpand = run.onOpenExpanded
        let openExpanded: @convention(block) () -> Void = { DispatchQueue.main.async { onExpand() } }
        let copy: @convention(block) (String) -> Void = { text in nidusCopyToClipboard(text) }

        let cardsObj = JSValue(newObjectIn: ctx)!
        cardsObj.setObject(all, forKeyedSubscript: "all" as NSString)
        cardsObj.setObject(get, forKeyedSubscript: "get" as NSString)
        cardsObj.setObject(add, forKeyedSubscript: "add" as NSString)
        cardsObj.setObject(update, forKeyedSubscript: "update" as NSString)
        cardsObj.setObject(remove, forKeyedSubscript: "remove" as NSString)

        let nidus = JSValue(newObjectIn: ctx)!
        nidus.setObject(cardsObj, forKeyedSubscript: "cards" as NSString)
        nidus.setObject(openCard, forKeyedSubscript: "openCard" as NSString)
        nidus.setObject(openExpanded, forKeyedSubscript: "openExpanded" as NSString)
        let clip = JSValue(newObjectIn: ctx)!
        clip.setObject(copy, forKeyedSubscript: "copy" as NSString)
        nidus.setObject(clip, forKeyedSubscript: "clipboard" as NSString)

        // nidus.library — the OPTIONAL cross-project bank (only available when we know the vault + file).
        // save/remove are owner-gated; importHere makes an independent copy; all() flags `ownedHere`.
        if let vault = run.vaultURL, let pfile = file {
            let root = vault.appendingPathComponent("_library", isDirectory: true)
            let toolID = origin
            let folder = pfile.deletingLastPathComponent()
            let owner = ToolLibraryStore.projectKey(vault: vault, folder: folder)
            let libSave: @convention(block) (String) -> Bool = { id in
                ToolLibraryStore.save(cardID: id, projectFile: pfile, projectFolder: folder, root: root, toolID: toolID, owner: owner)
            }
            let libRemove: @convention(block) (String) -> Bool = { id in
                ToolLibraryStore.remove(cardID: id, root: root, toolID: toolID, owner: owner)
            }
            let libContains: @convention(block) (String) -> Bool = { id in
                ToolLibraryStore.contains(id, root: root, toolID: toolID)
            }
            let libAll: @convention(block) () -> [[String: Any]] = {
                ToolLibraryStore.entries(root: root, toolID: toolID).map { c in
                    var d = cardToDict(c)
                    d["ownedHere"] = (c.extra["_owner"] ?? "") == owner
                    return d
                }
            }
            let libImport: @convention(block) (String) -> Any = { id in
                ToolLibraryStore.importHere(entryID: id, projectFile: pfile, projectFolder: folder, root: root, toolID: toolID, origin: toolID).map(cardToDict) ?? NSNull()
            }
            let lib = JSValue(newObjectIn: ctx)!
            lib.setObject(libSave, forKeyedSubscript: "save" as NSString)
            lib.setObject(libRemove, forKeyedSubscript: "remove" as NSString)
            lib.setObject(libContains, forKeyedSubscript: "contains" as NSString)
            lib.setObject(libAll, forKeyedSubscript: "all" as NSString)
            lib.setObject(libImport, forKeyedSubscript: "importHere" as NSString)
            nidus.setObject(lib, forKeyedSubscript: "library" as NSString)
        }
        ctx.setObject(nidus, forKeyedSubscript: "nidus" as NSString)

        let ctxObj = JSValue(newObjectIn: ctx)!
        ctxObj.setObject(nidus, forKeyedSubscript: "nidus" as NSString)
        ctxObj.setObject(run.size, forKeyedSubscript: "size" as NSString)
        ctxObj.setObject(readCards().map(cardToDict), forKeyedSubscript: "cards" as NSString)
        return (ctx, tool, ctxObj)
    }

    // MARK: Card ↔ JS dict

    static func cardToDict(_ c: Card) -> [String: Any] {
        ["id": c.id, "title": c.title, "body": c.body, "images": c.images,
         "links": c.links.map { ["title": $0.title, "url": $0.url] },
         "extra": c.extra]
    }

    private static func cardFromDict(_ d: [String: Any], origin: String) -> Card {
        var card = Card.make(title: (d["title"] as? String) ?? "Untitled",
                             body: (d["body"] as? String) ?? "", origin: origin)
        if let extra = d["extra"] as? [String: Any] { card.extra = extra.mapValues { "\($0)" } }
        if let images = d["images"] as? [String] { card.images = images }
        return card
    }

    /// Builds a runtime ToolDescriptor from a manifest, so an installed tool appears in the library and
    /// on the board exactly like a built-in.
    static func descriptor(for tool: InstalledTool) -> ToolDescriptor {
        let m = tool.manifest
        // A declared hotkey becomes a quick action that opens the tool's expanded view (wired in
        // WorkspaceView). `kind` is unused for installed tools — they don't do line-append capture.
        let quick = m.hotkey?.first.map {
            ToolQuickAction(defaultHotkey: $0, label: LocalizedStringKey(m.name), kind: .idea)
        }
        return ToolDescriptor(
            id: m.id, title: LocalizedStringKey(m.name), defaultName: m.name,
            summary: LocalizedStringKey(m.summary), icon: m.icon,
            validSizes: Set(m.sizes.isEmpty ? [.small, .medium] : m.sizes),
            files: m.store,
            allowsMultiple: m.allowsMultiple,
            toolClass: m.shareable ? .collector : .widget,
            accepts: Set(m.accepts), produces: m.produces,
            quickAction: quick,
            makeView: { ctx in AnyView(InstalledToolTileView(tool: tool, context: ctx)) })
    }
}
