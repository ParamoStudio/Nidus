//
//  InstalledToolStore.swift
//  Nidus
//
//  Vault-wide store for INSTALLED tools: their `.js` files live in `_tools/` at the vault root (like
//  micro-tools in `_microtools/`), so installing one makes it available in every project, and it
//  syncs if the vault syncs. Install = copy a picked `.js` in; the tool then appears in the library.
//

import Foundation

enum InstalledToolStore {
    static let folderName = "_tools"

    static func folderURL(vaultURL: URL?) -> URL? {
        vaultURL?.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Every installed tool (sorted by name). Creates the folder on first use.
    static func installed(vaultURL: URL?) -> [InstalledTool] {
        guard let folder = folderURL(vaultURL: vaultURL) else { return [] }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "js" }
            .compactMap { InstalledToolEngine.load($0) }
            .sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
    }

    /// Copies an imported `.js` into `_tools/` (unique name on clash). Keeps it only if it parses as a
    /// valid tool. Returns the loaded tool.
    @discardableResult
    static func install(from src: URL, vaultURL: URL?) -> InstalledTool? {
        guard src.pathExtension.lowercased() == "js", let folder = folderURL(vaultURL: vaultURL) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        var dest = folder.appendingPathComponent(src.lastPathComponent)
        var n = 1
        let stem = src.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(stem)-\(n).js"); n += 1
        }
        do { try FileManager.default.copyItem(at: src, to: dest) } catch { return nil }
        guard let tool = InstalledToolEngine.load(dest) else {
            try? FileManager.default.removeItem(at: dest); return nil
        }
        return tool
    }

    /// Uninstalls a tool (removes its `.js`). Its per-project data `.md` files are left untouched.
    static func uninstall(_ tool: InstalledTool) {
        try? FileManager.default.removeItem(at: tool.sourceURL)
    }
}
