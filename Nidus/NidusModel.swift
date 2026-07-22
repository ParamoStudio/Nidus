//
//  NidusModel.swift
//  Nidus
//
//  Root app state. Orchestrates device identity + vault + nidus.json.
//

import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
@MainActor
final class NidusModel {
    /// This device's local identity (never synced).
    private(set) var device: DeviceIdentity

    /// The vault root, once chosen/restored.
    private(set) var vaultURL: URL? {
        didSet { reloadInstalledTools() }
    }

    /// Installed (`.js`) tools from the vault's `_tools/`, mirrored into `ToolRegistry`.
    private(set) var installedTools: [InstalledTool] = []

    /// In-memory contents of `nidus.json`.
    private(set) var config: NidusConfig?

    /// Last human-readable error to surface in the UI (non-fatal).
    var lastError: String?

    /// Bumped whenever a tool writes a file, so other tiles reload (cross-tile refresh).
    /// Also bumped on app re-activation to pick up external edits.
    private(set) var fileChangeTick = 0
    func notifyFileChange() { fileChangeTick &+= 1 }

    /// True while any in-workspace text field is focused, so plain-letter shortcuts don't fire.
    var isEditingText = false

    private let vaultStore = VaultStore()

    init() {
        device = DeviceIdentityStore.loadOrCreate()
        restoreVaultIfAvailable()
        reloadInstalledTools()   // didSet may not fire during init; load the restored vault's tools now
    }

    var hasVault: Bool { vaultURL != nil }

    /// Restores the vault chosen in previous launches, if any.
    private func restoreVaultIfAvailable() {
        guard vaultStore.hasStoredVault else { return }
        do {
            vaultURL = try vaultStore.restore()
            config = try vaultStore.ensureConfigExists()
        } catch VaultError.notAVault {
            // The vault was deleted / isn't valid anymore → clean first-run (no error banner).
            vaultURL = nil
        } catch {
            lastError = String(localized: "Could not restore the vault: \(error.localizedDescription)")
        }
    }

    /// Creates the vault inside the location the user picked (Nidus makes the NidusVault folder).
    func createVault(in parentURL: URL) {
        do {
            try vaultStore.createVault(in: parentURL)
            vaultURL = vaultStore.vaultURL
            config = try vaultStore.ensureConfigExists()
            lastError = nil
        } catch {
            lastError = String(localized: "Could not create the vault: \(error.localizedDescription)")
        }
    }

    /// Opens an existing NidusVault the user located (must carry the validity marker).
    func openExistingVault(at url: URL) {
        do {
            try vaultStore.openExistingVault(at: url)
            vaultURL = vaultStore.vaultURL
            config = try vaultStore.ensureConfigExists()
            lastError = nil
        } catch {
            lastError = String(localized: "Could not open that vault: \(error.localizedDescription)")
        }
    }

    func reportImportFailure(_ error: Error) {
        lastError = String(localized: "Could not pick the folder: \(error.localizedDescription)")
    }

    // MARK: - Installed tools (`_tools/`)

    /// Reloads `_tools/` and mirrors it into the tool registry so installed tools show in the library.
    func reloadInstalledTools() {
        installedTools = InstalledToolStore.installed(vaultURL: vaultURL)
        ToolRegistry.setInstalled(installedTools)
    }

    @discardableResult
    func installTool(from url: URL) -> InstalledTool? {
        let tool = InstalledToolStore.install(from: url, vaultURL: vaultURL)
        reloadInstalledTools()
        return tool
    }

    func uninstallTool(_ tool: InstalledTool) {
        InstalledToolStore.uninstall(tool)
        reloadInstalledTools()
        notifyFileChange()
    }

    // MARK: - Lookups (Tramo 1)

    func discipline(id: String) -> Discipline? {
        config?.disciplines.first { $0.id == id }
    }

    func project(disciplineID: String, projectID: String) -> Project? {
        discipline(id: disciplineID)?.projects.first { $0.id == projectID }
    }

    /// Builds a linked_location pointing at THIS device (§2.3).
    func linkedLocation(for url: URL) -> LinkedLocation {
        LinkedLocation(deviceId: device.id, deviceName: device.name, path: url.path)
    }

    // MARK: - Create disciplines and projects (Tramo 1)

    /// Creates a discipline: folder in the vault + entry in nidus.json.
    @discardableResult
    func createDiscipline(name: String) -> Discipline? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var cfg = config else { return nil }

        let folder = Slug.unique(Slug.make(trimmed), existing: Set(cfg.disciplines.map(\.folder)))
        let id = Slug.unique(Slug.make(trimmed), existing: Set(cfg.disciplines.map(\.id)))
        let discipline = Discipline(id: id, name: trimmed, folder: folder,
                                    cover: .makeDefault(), projects: [])

        do {
            guard let dir = vaultStore.url(forRelativePath: folder) else { return nil }
            try vaultStore.makeDirectory(at: dir)
            cfg.disciplines.append(discipline)
            try vaultStore.writeConfig(cfg)
            config = cfg
            lastError = nil
            return discipline
        } catch {
            lastError = String(localized: "Could not create the discipline: \(error.localizedDescription)")
            return nil
        }
    }

    /// Creates a project: folder + the four `.md` files with headers + entry in nidus.json.
    /// `id` is unique across ALL projects (required by Raycast's URL scheme).
    @discardableResult
    func createProject(in disciplineID: String, name: String, description: String? = nil,
                       icon: String? = nil, linkedLocation: LinkedLocation?) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var cfg = config,
              let dIdx = cfg.disciplines.firstIndex(where: { $0.id == disciplineID }) else { return nil }

        let discipline = cfg.disciplines[dIdx]
        let folder = Slug.unique(Slug.make(trimmed), existing: Set(discipline.projects.map(\.folder)))
        let allProjectIDs = Set(cfg.disciplines.flatMap { $0.projects.map(\.id) })
        let id = Slug.unique(Slug.make(trimmed), existing: allProjectIDs)
        let cleanDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(id: id, name: trimmed, folder: folder,
                              description: (cleanDescription?.isEmpty == false) ? cleanDescription : nil,
                              icon: icon ?? Project.defaultIcon,
                              linkedLocation: linkedLocation, layout: .makeDefault())

        do {
            guard let projectDir = vaultStore.url(forRelativePath: discipline.folder, folder) else { return nil }
            try vaultStore.makeDirectory(at: projectDir)
            for slot in project.layout?.grid ?? [] { ensureFiles(for: slot, in: projectDir) }
            cfg.disciplines[dIdx].projects.append(project)
            try vaultStore.writeConfig(cfg)
            config = cfg
            lastError = nil
            return project
        } catch {
            lastError = String(localized: "Could not create the project: \(error.localizedDescription)")
            return nil
        }
    }

    /// Updates an existing project's editable fields (name, description, icon, linked location) and,
    /// if the discipline changed, moves its folder within the vault to the new discipline. Disciplines
    /// are just Nidus-internal grouping — the project's real working folder (`linkedLocation`) is never
    /// touched. Returns the (possibly new) ProjectRef, or nil on failure.
    @discardableResult
    func updateProject(_ ref: ProjectRef, name: String, disciplineID newDisciplineID: String,
                       description: String?, icon: String?, linkedLocation: LinkedLocation?) -> ProjectRef? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, var cfg = config,
              let oldDIdx = cfg.disciplines.firstIndex(where: { $0.id == ref.disciplineID }),
              let pIdx = cfg.disciplines[oldDIdx].projects.firstIndex(where: { $0.id == ref.projectID }),
              let newDIdx = cfg.disciplines.firstIndex(where: { $0.id == newDisciplineID })
        else { return nil }

        let cleanDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        var project = cfg.disciplines[oldDIdx].projects[pIdx]
        let oldName = project.name
        project.name = trimmedName
        project.description = (cleanDescription?.isEmpty == false) ? cleanDescription : nil
        project.icon = icon ?? Project.defaultIcon
        project.linkedLocation = linkedLocation

        do {
            if newDisciplineID == ref.disciplineID {
                // Keep the vault folder name in step with the project name when the name changed (so a
                // renamed fork stops reading "…-forked-3"). Unique against siblings AND disk.
                if trimmedName != oldName {
                    let discFolder = cfg.disciplines[oldDIdx].folder
                    let siblings = Set(cfg.disciplines[oldDIdx].projects.enumerated()
                        .filter { $0.offset != pIdx }.map { $0.element.folder })
                    func folderTaken(_ s: String) -> Bool {
                        if siblings.contains(s) { return true }
                        return vaultStore.url(forRelativePath: discFolder, s)
                            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                    }
                    let base = Slug.make(trimmedName)
                    var newFolder = base; var k = 2
                    while newFolder != project.folder && folderTaken(newFolder) { newFolder = "\(base)-\(k)"; k += 1 }
                    if newFolder != project.folder,
                       let oldDir = vaultStore.url(forRelativePath: discFolder, project.folder),
                       let newDir = vaultStore.url(forRelativePath: discFolder, newFolder),
                       FileManager.default.fileExists(atPath: oldDir.path) {
                        try FileManager.default.moveItem(at: oldDir, to: newDir)
                        migrateLibraryOwner(from: "\(discFolder)/\(project.folder)", to: "\(discFolder)/\(newFolder)")
                        project.folder = newFolder
                    }
                }
                cfg.disciplines[oldDIdx].projects[pIdx] = project
            } else {
                // Move the project's vault folder into the new discipline (its own slug stays unless
                // it collides there). The folder carries everything: .md files, icon image, etc.
                let oldDiscFolder = cfg.disciplines[oldDIdx].folder
                let newDisc = cfg.disciplines[newDIdx]
                let newFolder = Slug.unique(project.folder, existing: Set(newDisc.projects.map(\.folder)))
                if let oldDir = vaultStore.url(forRelativePath: oldDiscFolder, project.folder),
                   let newDir = vaultStore.url(forRelativePath: newDisc.folder, newFolder),
                   FileManager.default.fileExists(atPath: oldDir.path) {
                    try FileManager.default.moveItem(at: oldDir, to: newDir)
                }
                project.folder = newFolder
                cfg.disciplines[oldDIdx].projects.remove(at: pIdx)
                cfg.disciplines[newDIdx].projects.append(project)
            }
            try vaultStore.writeConfig(cfg)
            config = cfg
            lastError = nil
            notifyFileChange()
            return ProjectRef(disciplineID: newDisciplineID, projectID: project.id)
        } catch {
            lastError = String(localized: "Could not update the project: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Project lifecycle: status, pinning, fork, permanent delete

    /// Sets a project's lifecycle status (active is stored as nil to keep nidus.json clean). Setting a
    /// non-active status also unpins it — pins are for the working set.
    func setStatus(_ ref: ProjectRef, _ status: ProjectStatus) {
        mutateProject(ref) { $0.status = status.stored }
        if status != .active { setPinned(ref, false) }
    }

    func status(for ref: ProjectRef) -> ProjectStatus { ProjectStatus(hit(for: ref)?.project.status) }

    // MARK: Pinning (global, ordered, max 3)

    func isPinned(_ ref: ProjectRef) -> Bool { config?.pinnedProjects.contains(ref.projectID) ?? false }

    var pinnedCount: Int { config?.pinnedProjects.count ?? 0 }

    /// Pins/unpins a project. Refuses a 4th pin (returns false); the user unpins one first.
    @discardableResult
    func setPinned(_ ref: ProjectRef, _ pinned: Bool) -> Bool {
        guard var cfg = config else { return false }
        let already = cfg.pinnedProjects.contains(ref.projectID)
        if pinned {
            guard !already else { return true }
            guard cfg.pinnedProjects.count < NidusConfig.maxPinned else { return false }
            cfg.pinnedProjects.append(ref.projectID)
        } else {
            guard already else { return true }
            cfg.pinnedProjects.removeAll { $0 == ref.projectID }
        }
        writeConfig(cfg)
        return true
    }

    @discardableResult
    func togglePin(_ ref: ProjectRef) -> Bool { setPinned(ref, !isPinned(ref)) }

    /// The pinned projects as hits, in pin order, skipping any that no longer exist.
    var pinnedHits: [ProjectHit] {
        (config?.pinnedProjects ?? []).compactMap { id in allProjects.first { $0.project.id == id } }
    }

    /// Projects that were forked FROM `ref` (the reverse of `forkedFrom`) — for the "Forks" menu.
    func forks(of ref: ProjectRef) -> [ProjectHit] {
        allProjects.filter {
            guard let f = $0.project.forkedFrom else { return false }
            return f.disciplineID == ref.disciplineID && f.projectID == ref.projectID
        }
    }

    /// What the Greeting surfaces (up to 3): pinned projects first, then the most-recent to fill.
    var openingProjects: [ProjectHit] {
        var out = pinnedHits
        let seen = Set(out.map(\.id))
        for hit in recentProjects where !seen.contains(hit.id) && out.count < NidusConfig.maxPinned {
            out.append(hit)
        }
        return Array(out.prefix(NidusConfig.maxPinned))
    }

    // MARK: Fork

    /// Duplicates a project — its whole vault folder (every tool `.md`, Notebook, `_assets`, blueprint,
    /// reference boards, icon) plus its nidus.json entry — into the SAME discipline, named
    /// "<name> (Forked)", with `forkedFrom` pointing back at the original. The library bank is NOT
    /// copied (a fork is a new project; it can re-save to the bank itself). Returns the new ref.
    @discardableResult
    func forkProject(_ ref: ProjectRef) -> ProjectRef? {
        guard var cfg = config,
              let dIdx = cfg.disciplines.firstIndex(where: { $0.id == ref.disciplineID }),
              let pIdx = cfg.disciplines[dIdx].projects.firstIndex(where: { $0.id == ref.projectID })
        else { return nil }

        let discipline = cfg.disciplines[dIdx]
        var fork = discipline.projects[pIdx]

        // Unique NAME within the discipline: "X (Forked)", then "X (Forked) 2"… so two forks never look
        // identical in the sidebar.
        let existingNames = Set(discipline.projects.map(\.name))
        var newName = "\(fork.name) (Forked)"
        if existingNames.contains(newName) {
            var n = 2
            while existingNames.contains("\(fork.name) (Forked) \(n)") { n += 1 }
            newName = "\(fork.name) (Forked) \(n)"
        }
        let allIDs = Set(cfg.disciplines.flatMap { $0.projects.map(\.id) })
        let newID = Slug.unique(Slug.make(newName), existing: allIDs)

        // Unique FOLDER checking BOTH nidus.json AND disk — an orphaned folder (e.g. a prior delete
        // whose folder removal failed) must never be chosen, or copyItem throws and forking silently
        // fails forever (the bug this fixes).
        let configFolders = Set(discipline.projects.map(\.folder))
        func folderTaken(_ slug: String) -> Bool {
            if configFolders.contains(slug) { return true }
            if let url = vaultStore.url(forRelativePath: discipline.folder, slug) {
                return FileManager.default.fileExists(atPath: url.path)
            }
            return false
        }
        let base = Slug.make(newName)
        var newFolder = base
        var k = 2
        while folderTaken(newFolder) { newFolder = "\(base)-\(k)"; k += 1 }

        // Copy the folder on disk (everything the project owns travels with it).
        if let srcDir = vaultStore.url(forRelativePath: discipline.folder, fork.folder),
           let dstDir = vaultStore.url(forRelativePath: discipline.folder, newFolder),
           FileManager.default.fileExists(atPath: srcDir.path) {
            do { try FileManager.default.copyItem(at: srcDir, to: dstDir) }
            catch { lastError = String(localized: "Could not fork the project: \(error.localizedDescription)"); return nil }
        }

        fork.id = newID
        fork.name = newName
        fork.folder = newFolder
        fork.status = nil                                   // a fork starts active
        fork.forkedFrom = ProjectFork(disciplineID: ref.disciplineID, projectID: ref.projectID)
        cfg.disciplines[dIdx].projects.append(fork)
        writeConfig(cfg)
        notifyFileChange()
        return ProjectRef(disciplineID: ref.disciplineID, projectID: newID)
    }

    // MARK: Permanent delete (deprecated only)

    /// Permanently removes a project: its vault folder AND its nidus.json entry. Guarded to `deprecated`
    /// status (the UI only offers it there). DESTRUCTIVE and irreversible. The cross-project library
    /// bank is deliberately left untouched — a banked entry outlives the project that contributed it
    /// (it just becomes owner-orphaned: still importable by others, no longer removable).
    @discardableResult
    func deleteProjectPermanently(_ ref: ProjectRef) -> Bool {
        guard var cfg = config,
              let dIdx = cfg.disciplines.firstIndex(where: { $0.id == ref.disciplineID }),
              let pIdx = cfg.disciplines[dIdx].projects.firstIndex(where: { $0.id == ref.projectID }),
              ProjectStatus(cfg.disciplines[dIdx].projects[pIdx].status) == .deprecated
        else { return false }

        let folder = cfg.disciplines[dIdx].projects[pIdx].folder
        if let dir = vaultStore.url(forRelativePath: cfg.disciplines[dIdx].folder, folder),
           FileManager.default.fileExists(atPath: dir.path) {
            // Surface a failure rather than swallow it: a silently-orphaned folder is exactly what used
            // to block re-forking. (forkProject is now also disk-aware, so this is belt-and-braces.)
            do { try FileManager.default.removeItem(at: dir) }
            catch { lastError = String(localized: "Removed from Nidus, but the folder couldn't be deleted: \(error.localizedDescription)") }
        }
        cfg.disciplines[dIdx].projects.remove(at: pIdx)
        cfg.pinnedProjects.removeAll { $0 == ref.projectID }
        writeConfig(cfg)
        notifyFileChange()
        return true
    }

    /// When a project's vault folder is renamed, keep any cross-project library entries it OWNS pointing
    /// at the new folder path (the bank's `_owner` key is that vault-relative path).
    private func migrateLibraryOwner(from oldKey: String, to newKey: String) {
        guard oldKey != newKey, let vault = vaultURL else { return }
        let libRoot = vault.appendingPathComponent("_library", isDirectory: true)
        guard let toolDirs = try? FileManager.default.contentsOfDirectory(at: libRoot, includingPropertiesForKeys: nil) else { return }
        for toolDir in toolDirs {
            let file = toolDir.appendingPathComponent("library.md")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            var cards = CardStore.read(from: file)
            var changed = false
            for i in cards.indices where cards[i].extra["_owner"] == oldKey {
                cards[i].extra["_owner"] = newKey; changed = true
            }
            if changed { CardStore.write(cards, to: file) }
        }
    }

    /// Persist a mutated config, updating the published copy. Central so lifecycle edits share one path.
    private func writeConfig(_ cfg: NidusConfig) {
        do { try vaultStore.writeConfig(cfg); config = cfg; lastError = nil }
        catch { lastError = String(localized: "Could not save: \(error.localizedDescription)") }
    }

    /// Moves a card between tool files losslessly: it lands in `dest` carrying everything (notes,
    /// images, extra fields), with `origin` set to where it came from and `modified` bumped.
    func moveCard(id: String, from source: URL, to dest: URL, origin: String) {
        guard source.standardizedFileURL != dest.standardizedFileURL else { return }
        guard var card = CardStore.read(from: source).first(where: { $0.id == id }) else { return }
        card.origin = origin
        card.modified = Date()
        CardStore.remove(id: id, from: source)
        CardStore.append(card, to: dest)
        notifyFileChange()
    }

    // MARK: - Task tags (shared bank, like disciplines)

    var allTags: [TaskTag] { config?.tags ?? [] }
    func tag(id: String) -> TaskTag? { config?.tags.first { $0.id == id } }
    func tags(ids: [String]) -> [TaskTag] { ids.compactMap { tag(id: $0) } }

    /// Returns the tag with this name, creating it (next palette colour) if new. Persists to nidus.json.
    @discardableResult
    func createOrFindTag(named raw: String) -> TaskTag? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var cfg = config else { return nil }
        if let hit = cfg.tags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return hit
        }
        let id = Slug.unique(Slug.make(name), existing: Set(cfg.tags.map(\.id)))
        let tag = TaskTag(id: id, name: name, color: cfg.tags.count % TagPalette.count)
        cfg.tags.append(tag)
        do { try vaultStore.writeConfig(cfg); config = cfg } catch { lastError = error.localizedDescription }
        return tag
    }

    /// Changes a tag's colour (0…7) everywhere it's used.
    func setTagColor(_ id: String, to color: Int) {
        guard var cfg = config, let i = cfg.tags.firstIndex(where: { $0.id == id }) else { return }
        cfg.tags[i].color = ((color % TagPalette.count) + TagPalette.count) % TagPalette.count
        do { try vaultStore.writeConfig(cfg); config = cfg; notifyFileChange() }
        catch { lastError = error.localizedDescription }
    }

    /// Renames a tag (keeps its id, so tasks stay linked).
    func renameTag(_ id: String, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var cfg = config, let i = cfg.tags.firstIndex(where: { $0.id == id }) else { return }
        cfg.tags[i].name = name
        do { try vaultStore.writeConfig(cfg); config = cfg; notifyFileChange() }
        catch { lastError = error.localizedDescription }
    }

    /// Deletes a tag from the bank. Tasks still holding its id just stop showing it (harmless).
    func deleteTag(_ id: String) {
        guard var cfg = config, let i = cfg.tags.firstIndex(where: { $0.id == id }) else { return }
        cfg.tags.remove(at: i)
        do { try vaultStore.writeConfig(cfg); config = cfg; notifyFileChange() }
        catch { lastError = error.localizedDescription }
    }

    /// Tags matching a query (for autocomplete), excluding ones already chosen.
    func tagSuggestions(matching query: String, excluding used: [String]) -> [TaskTag] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return allTags.filter { !used.contains($0.id) && (q.isEmpty || $0.name.lowercased().contains(q)) }
    }

    /// Replaces the project's quick actions (the card shortcuts). Nil-stores an empty list.
    func setQuickActions(_ ref: ProjectRef, _ actions: [QuickAction]) {
        guard var cfg = config,
              let dIdx = cfg.disciplines.firstIndex(where: { $0.id == ref.disciplineID }),
              let pIdx = cfg.disciplines[dIdx].projects.firstIndex(where: { $0.id == ref.projectID })
        else { return }
        cfg.disciplines[dIdx].projects[pIdx].quickActions = actions.isEmpty ? nil : actions
        do { try vaultStore.writeConfig(cfg); config = cfg; lastError = nil }
        catch { lastError = String(localized: "Could not save quick actions: \(error.localizedDescription)") }
    }

    /// Icons the user dropped in the vault's `_icons/` folder (SVG/PNG) — shown in the icon picker.
    var userIcons: [URL] { vaultStore.userIconFiles() }

    /// Save a custom icon (imported file or a user-icon) as the project's icon: rasterised to a
    /// 256px PNG inside its folder, preserving alpha. Set the project's `icon` to "image".
    func setProjectIconImage(_ ref: ProjectRef, fromImageAt sourceURL: URL) {
        guard let folder = projectFolderURL(ref) else { return }
        let dest = folder.appendingPathComponent(ProjectGlyph.imageFileName)
        // Editing without changing the image: the chosen URL IS the existing icon — nothing to copy.
        if sourceURL.standardizedFileURL == dest.standardizedFileURL { return }
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let side: CGFloat = 256
        guard let src = NSImage(contentsOf: sourceURL) else { return }
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        src.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero,
                 operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        #else
        guard let data = try? Data(contentsOf: sourceURL), let ui = UIImage(data: data),
              let png = ui.pngData() else { return }
        #endif
        try? png.write(to: dest)
        notifyFileChange()
    }

    /// Copies a picked image into the project's `_assets/` folder and returns its relative path
    /// ("_assets/<uuid>.<ext>"), for attaching to a card. Keeps the original file (not rasterised),
    /// so it survives the card moving between tools of the same project.
    func importCardImage(from sourceURL: URL, intoProjectFolder folderURL: URL) -> String? {
        let assets = folderURL.appendingPathComponent("_assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.copyItem(at: sourceURL, to: assets.appendingPathComponent(name))
            return "_assets/\(name)"
        } catch {
            lastError = String(localized: "Could not add the image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Saves raw image data (e.g. from a paste) into `_assets/` and returns its relative path.
    func saveCardImage(_ data: Data, ext: String, intoProjectFolder folderURL: URL) -> String? {
        let assets = folderURL.appendingPathComponent("_assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).\(ext.isEmpty ? "png" : ext)"
        do {
            try data.write(to: assets.appendingPathComponent(name))
            return "_assets/\(name)"
        } catch {
            lastError = String(localized: "Could not add the image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Deletes a card's image file from `_assets/` so removing an image (or a card) doesn't leave
    /// orphaned files accumulating. Only touches paths inside `_assets/`.
    func deleteCardImage(_ relativePath: String, inProjectFolder folderURL: URL) {
        guard relativePath.hasPrefix("_assets/") else { return }
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(relativePath))
    }

    // MARK: - Project search (Greeting Panel, Tramo 1)

    /// All projects across all disciplines, paired with their discipline.
    var allProjects: [ProjectHit] {
        (config?.disciplines ?? []).flatMap { discipline in
            discipline.projects.map { ProjectHit(discipline: discipline, project: $0) }
        }
    }

    /// Fuzzy search for the Greeting Panel. Matches by project name AND by discipline name: typing
    /// a discipline (or getting close — it's fuzzy) surfaces that discipline's projects most-recent
    /// first, even if the project name doesn't contain the query (e.g. "ceram" → all Ceramics
    /// projects). A name match always outranks a discipline-only match. Empty query → nothing.
    func searchProjects(_ query: String) -> [ProjectHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let recents = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        func recency(_ hit: ProjectHit) -> Int { recents.firstIndex(of: hit.project.id) ?? Int.max }

        return allProjects
            .compactMap { hit -> (ProjectHit, Int)? in
                let name = Fuzzy.score(query: trimmed, candidate: hit.project.name)
                let disc = Fuzzy.score(query: trimmed, candidate: hit.discipline.name)
                // Name matches get a big boost so they sit above any discipline-only match; the
                // latter pulls in the whole discipline (ranked by recency in the sort below).
                let score: Int?
                if let name { score = name + 100 } else if let disc { score = disc } else { score = nil }
                return score.map { (hit, $0) }
            }
            .sorted { a, b in a.1 != b.1 ? a.1 > b.1 : recency(a.0) < recency(b.0) }
            .map(\.0)
    }

    func hit(for ref: ProjectRef) -> ProjectHit? {
        guard let discipline = discipline(id: ref.disciplineID),
              let project = discipline.projects.first(where: { $0.id == ref.projectID }) else { return nil }
        return ProjectHit(discipline: discipline, project: project)
    }

    /// The project's folder inside the vault, where its tool `.md` files live.
    func projectFolderURL(_ ref: ProjectRef) -> URL? {
        guard let hit = hit(for: ref) else { return nil }
        return vaultStore.url(forRelativePath: hit.discipline.folder, hit.project.folder)
    }

    // MARK: - Layout editing (Customize Mode, Tramo 2.4)

    /// Adds a tool to the project's grid at the given area, sized to the largest valid size
    /// that fits the area. Persists `nidus.json`.
    func addTool(_ ref: ProjectRef, toolID: String, atCol col: Int, row: Int, areaCols: Int, areaRows: Int) {
        let descriptor = ToolRegistry.descriptor(for: toolID)
        let size = bestFit(for: descriptor, cols: areaCols, rows: areaRows)
        let folderURL = projectFolderURL(ref)
        let existing = hit(for: ref)?.project.layout?.grid ?? []
        let resolved = resolveInstance(toolID: toolID, in: folderURL, existing: existing)

        if let folderURL {
            for file in resolved.files {
                try? MarkdownStore.ensureToolFile(at: folderURL.appendingPathComponent(file),
                                                  toolID: toolID, name: descriptor.defaultName)
            }
        }
        // Canonical first instance keeps nil files (uses the tool's declared names).
        let isDuplicate = resolved.id != toolID
        let storedFiles = isDuplicate ? resolved.files : nil
        // Distinguish duplicates with a numbered default name until rename lands.
        let name = isDuplicate
            ? "\(descriptor.defaultName) \(resolved.id.dropFirst(toolID.count + 1))"
            : nil
        mutateProject(ref) { project in
            var layout = project.layout ?? ProjectLayout(overviewTool: "deadline-calendar", grid: [])
            layout.grid.append(ToolSlot(id: resolved.id, tool: toolID, name: name,
                                        size: size.rawValue, col: col, row: row, files: storedFiles))
            project.layout = layout
        }
    }

    /// Creates the `.md` files an instance owns, each with its self-describing header.
    private func ensureFiles(for slot: ToolSlot, in folderURL: URL) {
        let descriptor = ToolRegistry.descriptor(for: slot.tool)
        let files = slot.files ?? descriptor.files
        let name = slot.name ?? descriptor.defaultName
        for file in files {
            try? MarkdownStore.ensureToolFile(at: folderURL.appendingPathComponent(file),
                                              toolID: slot.tool, name: name)
        }
    }

    /// Resolves a unique instance id + file set for a new tool, suffixing on collision
    /// (ideas.md → ideas-2.md) so duplicate instances don't clash.
    private func resolveInstance(toolID: String, in folderURL: URL?,
                                 existing: [ToolSlot]) -> (id: String, files: [String]) {
        let descriptor = ToolRegistry.descriptor(for: toolID)
        let used = Set(existing.flatMap { $0.files ?? ToolRegistry.descriptor(for: $0.tool).files })
        var n = 1
        while true {
            let candidate = descriptor.files.map { suffixedFile($0, n) }
            let clashes = candidate.contains { used.contains($0) || fileOnDisk($0, folderURL) }
            if !clashes {
                return (n == 1 ? toolID : "\(toolID)-\(n)", candidate)
            }
            n += 1
        }
    }

    private func suffixedFile(_ file: String, _ n: Int) -> String {
        guard n > 1 else { return file }
        let url = URL(fileURLWithPath: file)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
    }

    private func fileOnDisk(_ name: String, _ folder: URL?) -> Bool {
        guard let folder else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }

    /// Replaces the whole grid (used by drag-move / resize). Persists `nidus.json`.
    func setGrid(_ ref: ProjectRef, _ grid: [ToolSlot]) {
        mutateProject(ref) { $0.layout?.grid = grid }
    }

    /// Sets a tool instance's quick-add hotkey override (nil/empty → revert to the descriptor's
    /// default). Per-instance, so a duplicated tool (e.g. "Recipes") can get its own letter.
    func setToolHotkey(_ ref: ProjectRef, slotID: String, to hotkey: String?) {
        mutateProject(ref) { project in
            guard var layout = project.layout,
                  let i = layout.grid.firstIndex(where: { $0.id == slotID }) else { return }
            let trimmed = hotkey?.trimmingCharacters(in: .whitespaces).lowercased()
            layout.grid[i].hotkey = (trimmed?.isEmpty ?? true) ? nil : String(trimmed!.prefix(1))
            project.layout = layout
        }
    }

    /// Removes a tool from the board but keeps the instance (and its `.md`) in `detached`, so it
    /// can be re-attached later (no duplicate). The Inbox is mandatory and can't be removed (§3.3).
    func removeTool(_ ref: ProjectRef, slotID: String) {
        mutateProject(ref) { project in
            guard var layout = project.layout,
                  let i = layout.grid.firstIndex(where: { $0.id == slotID }),
                  layout.grid[i].tool != "inbox" else { return }
            let slot = layout.grid.remove(at: i)
            layout.detached = (layout.detached ?? []) + [slot]
            project.layout = layout
        }
    }

    /// Permanently abandons an instance (from the board or the detached pool): removes the app's link
    /// to it, and marks its `.md` file(s) as deprecated — but keeps them on disk (archival). Inbox is
    /// exempt. Distinct from `removeTool`, which only detaches (re-attachable, unchanged files).
    func abandonTool(_ ref: ProjectRef, slotID: String) {
        guard let folder = projectFolderURL(ref) else { return }
        var removed: ToolSlot?
        mutateProject(ref) { project in
            guard var layout = project.layout else { return }
            if let i = layout.grid.firstIndex(where: { $0.id == slotID }), layout.grid[i].tool != "inbox" {
                removed = layout.grid.remove(at: i)
            } else if let i = (layout.detached ?? []).firstIndex(where: { $0.id == slotID }) {
                removed = layout.detached!.remove(at: i)
            }
            project.layout = layout
        }
        if let removed {
            let files = removed.files ?? ToolRegistry.descriptor(for: removed.tool).files
            for f in files { MarkdownStore.markDeprecated(at: folder.appendingPathComponent(f)) }
        }
    }

    /// Re-attaches a detached instance to the board at the given area (reuses its files/data).
    func attachTool(_ ref: ProjectRef, slotID: String, atCol col: Int, row: Int,
                    areaCols: Int, areaRows: Int) {
        mutateProject(ref) { project in
            guard var layout = project.layout,
                  let i = (layout.detached ?? []).firstIndex(where: { $0.id == slotID }) else { return }
            var slot = layout.detached!.remove(at: i)
            let descriptor = ToolRegistry.descriptor(for: slot.tool)
            // Remember the instance's last size: keep it if it fits the area, else nearest that does.
            let last = slot.toolSize
            let size = (descriptor.validSizes.contains(last)
                        && last.columns <= areaCols && last.rows <= areaRows)
                ? last : bestFit(for: descriptor, cols: areaCols, rows: areaRows)
            slot.col = col; slot.row = row; slot.size = size.rawValue
            layout.grid.append(slot)
            project.layout = layout
        }
    }

    /// Renames a tool instance: updates its title and rewrites the `.md` self-describing header.
    func renameTool(_ ref: ProjectRef, slotID: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folderURL = projectFolderURL(ref)
        mutateProject(ref) { project in
            guard var layout = project.layout,
                  let i = layout.grid.firstIndex(where: { $0.id == slotID }) else { return }
            layout.grid[i].name = trimmed
            project.layout = layout
            if let folderURL {
                let descriptor = ToolRegistry.descriptor(for: layout.grid[i].tool)
                for file in (layout.grid[i].files ?? descriptor.files) {
                    try? MarkdownStore.renameHeader(at: folderURL.appendingPathComponent(file),
                                                    to: trimmed)
                }
            }
        }
    }

    private func bestFit(for descriptor: ToolDescriptor, cols: Int, rows: Int) -> ToolSize {
        let fitting = ToolSize.allCases.filter {
            descriptor.validSizes.contains($0) && $0.columns <= cols && $0.rows <= rows
        }
        return fitting.max(by: { $0.columns * $0.rows < $1.columns * $1.rows }) ?? .small
    }

    /// Finds the project, applies `body`, and persists `nidus.json`.
    private func mutateProject(_ ref: ProjectRef, _ body: (inout Project) -> Void) {
        guard var cfg = config,
              let di = cfg.disciplines.firstIndex(where: { $0.id == ref.disciplineID }),
              let pi = cfg.disciplines[di].projects.firstIndex(where: { $0.id == ref.projectID })
        else { return }
        body(&cfg.disciplines[di].projects[pi])
        do {
            try vaultStore.writeConfig(cfg)
            config = cfg
            lastError = nil
        } catch {
            lastError = String(localized: "Could not save the layout: \(error.localizedDescription)")
        }
    }

    // MARK: - Content search (command palette) — card-aware, per instance

    /// Set by search to scroll to + flash a specific card. Tools observe it.
    var revealTarget: RevealTarget?
    func reveal(ref: ProjectRef, slotID: String, cardID: String) {
        revealTarget = RevealTarget(ref: ref, slotID: slotID, cardID: cardID,
                                    nonce: (revealTarget?.nonce ?? 0) + 1)
    }

    /// Searches the cards of every card-based tool instance. Project scope = current project only;
    /// app scope = every project. Each match points at its exact card + the instance it lives in.
    func searchContent(_ query: String, scope: SearchScope, current: ProjectRef) -> [ContentHit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let refs: [ProjectRef] = scope == .project ? [current] : allProjects.map(\.ref)
        var hits: [ContentHit] = []
        for ref in refs {
            guard let folder = projectFolderURL(ref), let h = hit(for: ref) else { continue }
            for slot in h.project.layout?.grid ?? [] {
                let desc = ToolRegistry.descriptor(for: slot.tool)
                switch desc.toolClass {           // only card-based tools own searchable cards
                case .collector, .worker, .archive: break
                default: continue
                }
                guard let declared = desc.files.first else { continue }
                let url = folder.appendingPathComponent(slot.files?.first ?? declared)
                for card in CardStore.read(from: url) {
                    guard (card.title + " " + card.body).lowercased().contains(q) else { continue }
                    let display = card.title.isEmpty
                        ? String(card.body.replacingOccurrences(of: "\n", with: " ").prefix(60))
                        : card.title
                    hits.append(ContentHit(ref: ref, projectName: h.project.name, toolID: slot.tool,
                                           slotID: slot.id, cardID: card.id, line: display))
                }
            }
        }
        return hits
    }

    // MARK: - Recents (device-local UI state, never in the vault)

    private let recentsKey = "nidus.recent.projects"
    private let recentsLimit = 6

    /// Recently opened projects, most recent first, filtered to ones that still exist.
    var recentProjects: [ProjectHit] {
        let ids = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        return ids.compactMap { id in
            allProjects.first { $0.project.id == id }
        }
    }

    func markOpened(_ ref: ProjectRef) {
        var ids = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        ids.removeAll { $0 == ref.projectID }
        ids.insert(ref.projectID, at: 0)
        if ids.count > recentsLimit { ids = Array(ids.prefix(recentsLimit)) }
        UserDefaults.standard.set(ids, forKey: recentsKey)
    }
}

/// A project together with the discipline it belongs to.
struct ProjectHit: Identifiable, Equatable {
    let discipline: Discipline
    let project: Project
    var id: String { project.id }
    var ref: ProjectRef { ProjectRef(disciplineID: discipline.id, projectID: project.id) }
}

/// A window's current project selection (one window = one project).
struct ProjectRef: Hashable {
    let disciplineID: String
    let projectID: String
}

/// One content-search match (command palette) — points at a specific card in a specific instance.
struct ContentHit: Identifiable {
    let id = UUID()
    let ref: ProjectRef
    let projectName: String
    let toolID: String     // tool type, for the palette icon/label
    let slotID: String     // the tool instance to reveal in
    let cardID: String     // the exact card to scroll to + flash
    let line: String       // display text (card title / snippet)
}

/// A request to reveal a specific card inside a specific tool instance (from search). Tools observe
/// it, scroll to the card and flash it. `nonce` re-triggers even when the same card is chosen twice.
struct RevealTarget: Equatable {
    let ref: ProjectRef
    let slotID: String
    let cardID: String
    var nonce: Int
}
