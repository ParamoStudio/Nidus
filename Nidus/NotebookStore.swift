//
//  NotebookStore.swift
//  Nidus
//
//  The Notebook's single source of truth is a real `Notebook` folder inside the PROJECT's own vault
//  folder (next to `_assets/`) — so it's portable, reaches iPad, and syncs (unlike the old Reference
//  Board, which lived in the external linked folder). Whatever files live there are what the library
//  shows: our own notes are `.md` with a small YAML frontmatter (title/id/created, never shown in the
//  UI); imported documents (pdf/txt/docx/odt/pages/rtf) are copied in as-is. A "group" is just a real
//  SUBFOLDER, rendered as an Apple Books-style shelf row. The only invented state is a tiny JSON
//  manifest recording which items are anchored (pinned) to the front of each row.
//

import Foundation

enum NotebookStore {
    static let folderName = "Notebook"
    static let manifestName = ".nidus-notebook"   // hidden anchor manifest

    /// Our own editable notes.
    static let noteExtensions: Set<String> = ["md", "markdown"]
    /// Imported documents — previewed via QuickLook, opened in their own app, never edited in Nidus.
    static let documentExtensions: Set<String> = ["txt", "pdf", "docx", "odt", "pages", "rtf"]
    /// Everything the importer accepts (anything else is rejected).
    static var importableExtensions: Set<String> { noteExtensions.union(documentExtensions) }

    // MARK: - Model

    /// One file in the Notebook: a note we own or an imported document.
    struct Item: Identifiable, Equatable {
        let url: URL
        let zone: String        // "" = root (no group)
        let isNote: Bool
        let title: String       // note: frontmatter title (or filename stem); document: filename stem
        let modified: Date
        var id: String { url.path }
        var filename: String { url.lastPathComponent }
        var ext: String { url.pathExtension.lowercased() }
    }

    /// A shelf row: the root (unlabeled) or a named group (a real subfolder). Items come
    /// anchored-first (in the manifest's order), then the rest newest-edited-first.
    struct Zone: Identifiable {
        let name: String        // "" = root
        var items: [Item]
        var anchored: [String]  // filenames anchored to the front, in order (max 2)
        var id: String { name.isEmpty ? "\u{1}root" : name }
        var isRoot: Bool { name.isEmpty }
    }

    /// Persisted per-row anchor list. `anchors[""]` is the root row.
    struct Manifest: Codable {
        var anchors: [String: [String]]
        init(anchors: [String: [String]] = [:]) { self.anchors = anchors }
    }

    static let maxAnchors = 2

    // MARK: - Folder + manifest

    static func folderURL(projectFolder: URL?) -> URL? {
        projectFolder?.appendingPathComponent(folderName, isDirectory: true)
    }

    @discardableResult
    static func ensure(_ folder: URL) -> URL? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: folder.path, isDirectory: &isDir) {
            do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return nil }
        } else if !isDir.boolValue {
            return nil
        }
        return folder
    }

    static func loadManifest(_ folder: URL) -> Manifest {
        let url = folder.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return Manifest() }
        return m
    }

    static func saveManifest(_ m: Manifest, _ folder: URL) {
        if let data = try? JSONEncoder().encode(m) {
            try? data.write(to: folder.appendingPathComponent(manifestName))
        }
    }

    // MARK: - Reading the library

    /// Every zone (root first, then groups alphabetically), each with its items ordered
    /// anchored-first then newest-edited. Reconciles the manifest (drops vanished anchors).
    static func load(projectFolder: URL?) -> [Zone] {
        // Read-only: do NOT ensure() (create) the folder just to list it — otherwise a just-deleted
        // project's Notebook folder gets re-created by a reload during the delete, orphaning it on disk.
        // The folder is created lazily on the first note/import (createNote → zoneURL → ensure).
        guard let folder = folderURL(projectFolder: projectFolder),
              FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let fm = FileManager.default

        // Root: files directly in the folder + the subfolders (each = a group).
        let rootEntries = (try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []

        var rootItems: [Item] = []
        var groupNames: [String] = []
        for url in rootEntries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                groupNames.append(url.lastPathComponent)
            } else if let item = item(at: url, zone: "") {
                rootItems.append(item)
            }
        }

        var manifest = loadManifest(folder)
        var zones: [Zone] = []
        zones.append(makeZone(name: "", items: rootItems, manifest: &manifest))

        for name in groupNames.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let dir = folder.appendingPathComponent(name, isDirectory: true)
            let entries = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let items = entries.compactMap { item(at: $0, zone: name) }
            zones.append(makeZone(name: name, items: items, manifest: &manifest))
        }

        // Persist any pruning done while building the zones.
        saveManifest(manifest, folder)
        return zones
    }

    /// Builds one zone: prunes stale anchors, then orders anchored-first + newest-edited.
    private static func makeZone(name: String, items: [Item], manifest: inout Manifest) -> Zone {
        let present = Set(items.map(\.filename))
        var anchors = (manifest.anchors[name] ?? []).filter { present.contains($0) }
        if anchors.count > maxAnchors { anchors = Array(anchors.prefix(maxAnchors)) }
        // Write back the pruned list (or clear it if empty).
        if anchors.isEmpty { manifest.anchors[name] = nil } else { manifest.anchors[name] = anchors }

        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.filename, $0) })
        let anchoredItems = anchors.compactMap { byName[$0] }
        let rest = items
            .filter { !anchors.contains($0.filename) }
            .sorted { $0.modified > $1.modified }
        return Zone(name: name, items: anchoredItems + rest, anchored: anchors)
    }

    /// Reads one file into an Item (nil if it isn't a note or an importable document).
    private static func item(at url: URL, zone: String) -> Item? {
        let ext = url.pathExtension.lowercased()
        let isNote = noteExtensions.contains(ext)
        guard isNote || documentExtensions.contains(ext) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let stem = url.deletingPathExtension().lastPathComponent
        let title: String
        if isNote, let meta = readMeta(url), let t = meta["title"], !t.isEmpty {
            title = t
        } else {
            title = stem
        }
        return Item(url: url, zone: zone, isNote: isNote, title: title, modified: modified)
    }

    // MARK: - Frontmatter (YAML: title / id / created — hidden from the editor)

    /// Splits a note file into its frontmatter dictionary and the body below it.
    static func parseFrontmatter(_ text: String) -> (meta: [String: String], body: String) {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return ([:], text) }
        let lines = text.components(separatedBy: "\n")
        // lines[0] == "---"; find the closing "---".
        var close = -1
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            close = i; break
        }
        guard close > 0 else { return ([:], text) }
        var meta: [String: String] = [:]
        for i in 1..<close {
            let line = lines[i]
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { meta[key] = value }
        }
        let body = lines[(close + 1)...].joined(separator: "\n")
        // Drop a single leading blank line left after the frontmatter.
        return (meta, body.hasPrefix("\n") ? String(body.dropFirst()) : body)
    }

    /// Reassembles a note file from its metadata and body.
    static func serialize(meta: [String: String], body: String) -> String {
        var out = "---\n"
        // Stable key order so files diff cleanly.
        for key in ["title", "id", "created"] where meta[key] != nil {
            out += "\(key): \(yamlValue(meta[key]!))\n"
        }
        for (key, value) in meta where !["title", "id", "created"].contains(key) {
            out += "\(key): \(yamlValue(value))\n"
        }
        out += "---\n\n"
        out += body
        return out
    }

    /// Quote a YAML scalar only if it contains something that would otherwise reparse wrong.
    private static func yamlValue(_ v: String) -> String {
        let needsQuote = v.contains(":") || v.contains("#") || v.hasPrefix(" ") || v.hasSuffix(" ")
            || v.hasPrefix("\"") || v.first == "-" || v.first == "["
        return needsQuote ? "\"\(v.replacingOccurrences(of: "\"", with: "\\\""))\"" : v
    }

    private static func readMeta(_ url: URL) -> [String: String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parseFrontmatter(text).meta
    }

    // MARK: - Notes: create / update / read body

    /// Creates a new note (empty by default) in the given zone, returns its Item.
    @discardableResult
    static func createNote(title rawTitle: String, body: String = "",
                           in zone: String, projectFolder: URL?) -> Item? {
        guard let dir = zoneURL(zone, projectFolder: projectFolder) else { return nil }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled" : rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let meta: [String: String] = [
            "title": title,
            "id": newID(),
            "created": iso.string(from: Date()),
        ]
        let dest = uniqueURL(in: dir, slug: slug(title), ext: "md")
        do { try serialize(meta: meta, body: body).write(to: dest, atomically: true, encoding: .utf8) }
        catch { return nil }
        return item(at: dest, zone: zone)
    }

    /// The raw body of a note (frontmatter stripped) for the editor.
    static func readBody(_ item: Item) -> String {
        guard item.isNote, let text = try? String(contentsOf: item.url, encoding: .utf8) else { return "" }
        return parseFrontmatter(text).body
    }

    /// Saves an edited note: preserves id/created, updates the title, writes the body. Renames the
    /// file to track the title's slug only when `renameToMatchTitle` is true (done on blur/close, not
    /// on every keystroke, to avoid churn). Returns the (possibly renamed) Item.
    @discardableResult
    static func updateNote(_ item: Item, title rawTitle: String, body: String,
                           renameToMatchTitle: Bool = true, projectFolder: URL?) -> Item? {
        guard item.isNote else { return nil }
        var meta = readMeta(item.url) ?? [:]
        if meta["id"] == nil { meta["id"] = newID() }
        if meta["created"] == nil { meta["created"] = iso.string(from: Date()) }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled" : rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        meta["title"] = title

        let text = serialize(meta: meta, body: body)
        // Rename the file to track the title's slug, unless the slug is unchanged (or not requested).
        let dir = item.url.deletingLastPathComponent()
        let desiredStem = slug(title)
        var dest = item.url
        if renameToMatchTitle && item.url.deletingPathExtension().lastPathComponent != desiredStem {
            dest = uniqueURL(in: dir, slug: desiredStem, ext: "md")
        }
        do {
            try text.write(to: dest, atomically: true, encoding: .utf8)
            if dest != item.url {
                try? FileManager.default.removeItem(at: item.url)
                renameInAnchors(from: item.filename, to: dest.lastPathComponent,
                                zone: item.zone, projectFolder: projectFolder)
            }
        } catch { return nil }
        return self.item(at: dest, zone: item.zone)
    }

    // MARK: - Import documents / text

    /// Copies an importable document into the zone (unique name on collision). nil if the type
    /// isn't accepted or the copy fails.
    @discardableResult
    static func importFile(_ src: URL, into zone: String, projectFolder: URL?) -> Item? {
        guard importableExtensions.contains(src.pathExtension.lowercased()),
              let dir = zoneURL(zone, projectFolder: projectFolder) else { return nil }
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let stem = src.deletingPathExtension().lastPathComponent
        let dest = uniqueURL(in: dir, slug: stem, ext: src.pathExtension)
        do { try FileManager.default.copyItem(at: src, to: dest) } catch { return nil }
        return item(at: dest, zone: zone)
    }

    /// Makes a new note from pasted plain text (first non-empty line becomes the title).
    @discardableResult
    static func createNoteFromText(_ text: String, in zone: String, projectFolder: URL?) -> Item? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed.components(separatedBy: "\n").first ?? "Untitled"
        var title = firstLine.trimmingCharacters(in: .whitespaces)
        // Strip a leading Markdown heading marker for the title.
        while title.hasPrefix("#") { title.removeFirst() }
        title = String(title.trimmingCharacters(in: .whitespaces).prefix(80))
        return createNote(title: title.isEmpty ? "Untitled" : title, body: trimmed,
                          in: zone, projectFolder: projectFolder)
    }

    // MARK: - Delete

    static func delete(_ item: Item, projectFolder: URL?) {
        try? FileManager.default.removeItem(at: item.url)
        setAnchor(item, anchored: false, projectFolder: projectFolder)   // also drop any anchor
    }

    // MARK: - Groups (zones = real subfolders)

    /// The on-disk folder for a zone ("" = the Notebook root). Creates it if needed.
    static func zoneURL(_ zone: String, projectFolder: URL?) -> URL? {
        guard let folder = folderURL(projectFolder: projectFolder), ensure(folder) != nil else { return nil }
        if zone.isEmpty { return folder }
        let dir = folder.appendingPathComponent(zone, isDirectory: true)
        return ensure(dir)
    }

    /// Moves items into a zone ("" = back to root). Files are physically moved; anchors follow.
    static func move(_ items: [Item], toZone zone: String, projectFolder: URL?) {
        guard let dir = zoneURL(zone, projectFolder: projectFolder) else { return }
        for it in items where it.zone != zone {
            let dest = uniqueURL(in: dir, slug: it.url.deletingPathExtension().lastPathComponent, ext: it.ext)
            do {
                try FileManager.default.moveItem(at: it.url, to: dest)
                setAnchor(it, anchored: false, projectFolder: projectFolder)   // moving clears the old anchor
            } catch { continue }
        }
    }

    /// A unique, filesystem-safe group name (used by "New group").
    static func uniqueZoneName(_ base: String, projectFolder: URL?) -> String {
        guard let folder = folderURL(projectFolder: projectFolder) else { return base }
        let clean = sanitize(base).isEmpty ? "Group" : sanitize(base)
        var name = clean, n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(clean) \(n)"; n += 1
        }
        return name
    }

    static func renameZone(_ old: String, to newName: String, projectFolder: URL?) {
        guard let folder = folderURL(projectFolder: projectFolder), !old.isEmpty else { return }
        let clean = sanitize(newName)
        guard !clean.isEmpty, clean != old else { return }
        let src = folder.appendingPathComponent(old, isDirectory: true)
        let dest = folder.appendingPathComponent(clean, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        do { try FileManager.default.moveItem(at: src, to: dest) } catch { return }
        var m = loadManifest(folder)
        if let a = m.anchors[old] { m.anchors[newName] = a; m.anchors[old] = nil; saveManifest(m, folder) }
    }

    /// Dissolves a group: its files move back to root, the (now empty) subfolder is removed.
    static func ungroup(_ zone: String, projectFolder: URL?) {
        guard !zone.isEmpty, let folder = folderURL(projectFolder: projectFolder) else { return }
        let dir = folder.appendingPathComponent(zone, isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let items = entries.compactMap { item(at: $0, zone: zone) }
        move(items, toZone: "", projectFolder: projectFolder)
        try? FileManager.default.removeItem(at: dir)
        var m = loadManifest(folder)
        if m.anchors[zone] != nil { m.anchors[zone] = nil; saveManifest(m, folder) }
    }

    // MARK: - Anchoring (pin to the front of a row, max 2)

    static func isAnchored(_ item: Item, manifest: Manifest) -> Bool {
        (manifest.anchors[item.zone] ?? []).contains(item.filename)
    }

    /// Toggles an item's anchor within its own row. Anchoring a 3rd evicts the oldest.
    static func toggleAnchor(_ item: Item, projectFolder: URL?) {
        guard let folder = folderURL(projectFolder: projectFolder) else { return }
        var m = loadManifest(folder)
        var list = m.anchors[item.zone] ?? []
        if let idx = list.firstIndex(of: item.filename) {
            list.remove(at: idx)
        } else {
            list.append(item.filename)
            if list.count > maxAnchors { list.removeFirst(list.count - maxAnchors) }
        }
        m.anchors[item.zone] = list.isEmpty ? nil : list
        saveManifest(m, folder)
    }

    private static func setAnchor(_ item: Item, anchored: Bool, projectFolder: URL?) {
        guard let folder = folderURL(projectFolder: projectFolder) else { return }
        var m = loadManifest(folder)
        var list = m.anchors[item.zone] ?? []
        list.removeAll { $0 == item.filename }
        if anchored {
            list.append(item.filename)
            if list.count > maxAnchors { list.removeFirst(list.count - maxAnchors) }
        }
        m.anchors[item.zone] = list.isEmpty ? nil : list
        saveManifest(m, folder)
    }

    private static func renameInAnchors(from old: String, to new: String, zone: String, projectFolder: URL?) {
        guard let folder = folderURL(projectFolder: projectFolder) else { return }
        var m = loadManifest(folder)
        guard var list = m.anchors[zone], let idx = list.firstIndex(of: old) else { return }
        list[idx] = new
        m.anchors[zone] = list
        saveManifest(m, folder)
    }

    // MARK: - Search

    /// Case-insensitive match on title, and (for notes) on the body text too.
    static func matches(_ item: Item, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if item.title.lowercased().contains(q) { return true }
        if item.filename.lowercased().contains(q) { return true }
        if item.isNote, let text = try? String(contentsOf: item.url, encoding: .utf8),
           text.lowercased().contains(q) { return true }
        return false
    }

    // MARK: - Naming helpers

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    private static func newID() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased() }

    /// A human filename stem from a title: keep spaces/case, drop only filesystem-hostile characters.
    static func slug(_ title: String) -> String {
        let cleaned = sanitize(title)
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(120))
    }

    private static func sanitize(_ s: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return s.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A unique URL in `dir` for `slug`.`ext`, adding " 2", " 3"… on collision (Finder-style).
    private static func uniqueURL(in dir: URL, slug rawSlug: String, ext: String) -> URL {
        let stem = rawSlug.isEmpty ? "Untitled" : rawSlug
        var url = dir.appendingPathComponent("\(stem).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(stem) \(n).\(ext)"); n += 1
        }
        return url
    }
}
