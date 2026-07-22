//
//  InstalledToolLibrary.swift
//  Nidus
//
//  The optional cross-project BANK for installed tools (see NIDUS-installable-tool-spec.md → nidus.library).
//  A tool can copy one of its cards into a shared folder at the vault root — `_library/<toolid>/` — so a
//  favourite (a tested glaze, say) survives its project and can be pulled into another one later. It is
//  just files: one `library.md` (CardStore format) + an `_assets/` for photos, per tool.
//
//  Single source of truth + a clear hierarchy: each bank entry records the project that saved it
//  (`extra["_owner"]`). ONLY that project may re-save or remove it. Any other project may `importHere`,
//  which makes an INDEPENDENT copy (new id, its own asset files) — it never mutates the bank entry.
//

import Foundation

enum ToolLibraryStore {

    // MARK: Paths (all under <vault>/_library/<toolid>/)

    private static func toolFolder(root: URL, toolID: String) -> URL {
        root.appendingPathComponent(toolID, isDirectory: true)
    }
    private static func file(root: URL, toolID: String) -> URL {
        toolFolder(root: root, toolID: toolID).appendingPathComponent("library.md")
    }
    private static func assetsDir(root: URL, toolID: String) -> URL {
        toolFolder(root: root, toolID: toolID).appendingPathComponent("_assets", isDirectory: true)
    }

    /// A stable owner id for a project: its folder path relative to the vault (e.g. "ceramics/teapot").
    static func projectKey(vault: URL, folder: URL) -> String {
        let v = vault.standardizedFileURL.pathComponents
        let f = folder.standardizedFileURL.pathComponents
        if f.count > v.count, Array(f.prefix(v.count)) == v {
            return f.dropFirst(v.count).joined(separator: "/")
        }
        return folder.lastPathComponent
    }

    // MARK: Reads

    static func entries(root: URL, toolID: String) -> [Card] {
        CardStore.read(from: file(root: root, toolID: toolID))
    }

    static func contains(_ id: String, root: URL, toolID: String) -> Bool {
        entries(root: root, toolID: toolID).contains { $0.id == id }
    }

    // MARK: Mutations (owner-gated)

    /// Copy a project card (+ its images) into the bank, stamped with `owner`. Returns false if the entry
    /// already exists and is owned by a DIFFERENT project (single source of truth).
    @discardableResult
    static func save(cardID: String, projectFile: URL, projectFolder: URL,
                     root: URL, toolID: String, owner: String) -> Bool {
        guard var card = CardStore.read(from: projectFile).first(where: { $0.id == cardID }) else { return false }
        let libFile = file(root: root, toolID: toolID)
        var list = CardStore.read(from: libFile)
        if let existing = list.first(where: { $0.id == cardID }), (existing.extra["_owner"] ?? "") != owner {
            return false
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: assetsDir(root: root, toolID: toolID), withIntermediateDirectories: true)
        // Copy assets into the bank; store ABSOLUTE paths so the entry displays from any project.
        card.images = card.images.compactMap { rel in
            let src = projectFolder.appendingPathComponent(rel)
            let dst = assetsDir(root: root, toolID: toolID).appendingPathComponent(src.lastPathComponent)
            if !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: src, to: dst) }
            return fm.fileExists(atPath: dst.path) ? dst.path : nil
        }
        card.extra["_owner"] = owner
        if let i = list.firstIndex(where: { $0.id == cardID }) { list[i] = card } else { list.append(card) }
        CardStore.write(list, to: libFile)
        return true
    }

    /// Remove an entry from the bank — only if `owner` created it. Also deletes its bank asset files.
    @discardableResult
    static func remove(cardID: String, root: URL, toolID: String, owner: String) -> Bool {
        let libFile = file(root: root, toolID: toolID)
        var list = CardStore.read(from: libFile)
        guard let entry = list.first(where: { $0.id == cardID }), (entry.extra["_owner"] ?? "") == owner else { return false }
        for p in entry.images where p.hasPrefix("/") { try? FileManager.default.removeItem(at: URL(fileURLWithPath: p)) }
        list.removeAll { $0.id == cardID }
        CardStore.write(list, to: libFile)
        return true
    }

    /// Copy a bank entry into a project as a NEW, independent card (+ fresh asset copies). The bank entry
    /// is never touched. Returns the new card, or nil if the entry is gone.
    static func importHere(entryID: String, projectFile: URL, projectFolder: URL,
                           root: URL, toolID: String, origin: String) -> Card? {
        guard let entry = entries(root: root, toolID: toolID).first(where: { $0.id == entryID }) else { return nil }
        var card = Card.make(title: entry.title, body: entry.body, origin: origin)
        card.extra = entry.extra
        card.extra.removeValue(forKey: "_owner")   // a copy is not owned by anyone
        let fm = FileManager.default
        let projAssets = projectFolder.appendingPathComponent("_assets", isDirectory: true)
        try? fm.createDirectory(at: projAssets, withIntermediateDirectories: true)
        card.images = entry.images.compactMap { p in
            let src = p.hasPrefix("/") ? URL(fileURLWithPath: p)
                                       : toolFolder(root: root, toolID: toolID).appendingPathComponent(p)
            let name = "\(UUID().uuidString).\(src.pathExtension)"
            let dst = projAssets.appendingPathComponent(name)
            guard (try? fm.copyItem(at: src, to: dst)) != nil else { return nil }
            return "_assets/\(name)"
        }
        CardStore.append(card, to: projectFile)
        return card
    }
}
