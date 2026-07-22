//
//  VaultStore.swift
//  Nidus
//
//  Persistent access to the NidusVault (Blueprint §2.1, §6, §9).
//
//  Vault creation flow: the user picks a *location*, and Nidus creates a `NidusVault`
//  folder inside it (with nidus.json). We keep a security-scoped bookmark to the chosen
//  parent (the URL the system actually grants us); the vault is `<parent>/NidusVault`.
//
//  macOS ↔ iPadOS difference:
//  - iPadOS is ALWAYS sandboxed. Access to a user-chosen folder only persists through a
//    bookmark + start/stopAccessingSecurityScopedResource().
//  - macOS runs WITHOUT sandbox here (open-source distribution, outside the App Store), so
//    filesystem access is unrestricted; startAccessing... returns `false` and that is NOT an
//    error — it simply isn't needed.
//  The bookmark is created with `options: []` on both platforms — `.withSecurityScope`
//  only applies to *sandboxed* macOS apps, which is not our case.
//

import Foundation

enum VaultError: LocalizedError {
    case noBookmarkStored
    case notAVault
    case configReadFailed(underlying: Error)
    case configWriteFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noBookmarkStored:
            return String(localized: "No vault has been chosen yet.")
        case .notAVault:
            return String(localized: "That folder isn't a Nidus vault. Pick a NidusVault folder Nidus created, or create a new one.")
        case .configReadFailed(let underlying):
            return String(localized: "Could not read nidus.json: \(underlying.localizedDescription)")
        case .configWriteFailed(let underlying):
            return String(localized: "Could not write nidus.json: \(underlying.localizedDescription)")
        }
    }
}

/// Persists the reference to the NidusVault and mediates access to `nidus.json`.
/// The bookmark lives in `UserDefaults` (local to the device), never inside the vault.
final class VaultStore {
    /// Name of the folder Nidus creates inside the user-chosen location.
    /// Brand/technical name — intentionally not localized.
    static let vaultFolderName = "NidusVault"

    /// Hidden marker Nidus drops in every vault it makes. Open-source, so it's not a real secret —
    /// just a recognizable token so the user can't accidentally point Nidus at a random folder.
    static let markerFileName = ".nidus-vault"
    static let markerToken = "nidus-vault-v1"
    /// Human-friendly file body (so technical users who find it don't worry); contains the token.
    static let markerBody = """
    Do not delete — this file marks this folder as a Nidus vault, so the app can verify it's a \
    genuine Nidus source. It's safe to keep and not used for anything else.

    \(markerToken)
    """

    private let bookmarkKey = "nidus.vault.root.bookmark"
    /// Whether the bookmark points directly at the vault (located existing) vs the parent (created).
    private let directKey = "nidus.vault.direct"
    private let defaults = UserDefaults.standard

    /// A folder is a valid Nidus vault if it holds the marker file with the expected token.
    func isValidVault(at url: URL) -> Bool {
        let marker = url.appendingPathComponent(Self.markerFileName)
        guard let content = try? String(contentsOf: marker, encoding: .utf8) else { return false }
        return content.contains(Self.markerToken)
    }

    /// The security-scoped URL we hold (the location the user picked).
    private var accessRoot: URL?
    private var isAccessing = false

    /// The vault itself: `<accessRoot>/NidusVault`.
    private(set) var vaultURL: URL?

    /// Did the user already choose a location in a previous launch?
    var hasStoredVault: Bool { defaults.data(forKey: bookmarkKey) != nil }

    // MARK: - Create / restore vault

    /// Creates the vault inside the location the user picked: makes the `NidusVault`
    /// folder (idempotent), bookmarks the location, opens access and ensures `nidus.json`.
    func createVault(in parentURL: URL) throws {
        // Hold access to the picked location while we create the folder and the bookmark.
        let didAccess = parentURL.startAccessingSecurityScopedResource()
        defer { if didAccess { parentURL.stopAccessingSecurityScopedResource() } }

        let vaultDir = parentURL.appendingPathComponent(Self.vaultFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)

        // Bookmark the picked parent (the URL the system actually granted); the vault is the
        // NidusVault subfolder.
        let data = try makeBookmarkData(for: parentURL)
        defaults.set(data, forKey: bookmarkKey)
        defaults.set(false, forKey: directKey)

        try resolveAndOpen()
        try ensureConfigExists() // writes the validity marker + scaffolding
    }

    /// Opens an EXISTING vault the user located. The folder itself must already be a valid Nidus
    /// vault (has the marker), so we bookmark it directly.
    func openExistingVault(at url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard isValidVault(at: url) else { throw VaultError.notAVault }

        let data = try makeBookmarkData(for: url)
        defaults.set(data, forKey: bookmarkKey)
        defaults.set(true, forKey: directKey)

        try resolveAndOpen()
        try ensureConfigExists()
    }

    /// Restores the stored vault on launch — but only if it's still a valid Nidus vault. If the
    /// folder was deleted or isn't a vault anymore, forget it so the first-run picker appears
    /// (instead of silently re-creating an empty folder).
    @discardableResult
    func restore() throws -> URL {
        try resolveAndOpen()
        guard let vaultURL else { throw VaultError.noBookmarkStored }
        guard isValidVault(at: vaultURL) else {
            defaults.removeObject(forKey: bookmarkKey)
            defaults.removeObject(forKey: directKey)
            self.vaultURL = nil
            accessRoot = nil
            throw VaultError.notAVault
        }
        return vaultURL
    }

    /// Resolves the stored bookmark and begins security-scoped access.
    private func resolveAndOpen() throws {
        guard let data = defaults.data(forKey: bookmarkKey) else {
            throw VaultError.noBookmarkStored
        }

        var isStale = false
        let root = try resolveBookmarkData(data, isStale: &isStale)

        // iPad requires explicitly starting access; on Mac (no sandbox) this returns
        // false and that's fine — access is unrestricted anyway.
        if root.startAccessingSecurityScopedResource() {
            isAccessing = true
        }

        // Refresh the bookmark if it went stale (the location was moved).
        if isStale {
            if let fresh = try? makeBookmarkData(for: root) {
                defaults.set(fresh, forKey: bookmarkKey)
            }
        }

        accessRoot = root
        // A located vault is the bookmarked folder itself; a created one is <parent>/NidusVault.
        vaultURL = defaults.bool(forKey: directKey)
            ? root
            : root.appendingPathComponent(Self.vaultFolderName, isDirectory: true)
        writeVaultPathSidecar()
    }

    /// A plain-text copy of the vault's absolute path, at a fixed, well-known location outside the
    /// vault — so external tools (the Raycast extension, shell scripts) can find the vault without
    /// decoding our security-scoped bookmark (opaque to anything that isn't this app). Not a secret,
    /// just a path; safe to read by anything running as this user.
    static let sidecarURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nidus", isDirectory: true)
        .appendingPathComponent("vault-path.txt")

    private func writeVaultPathSidecar() {
        guard let vaultURL else { return }
        let dir = Self.sidecarURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? vaultURL.path.write(to: Self.sidecarURL, atomically: true, encoding: .utf8)
    }

    /// Releases security-scoped access (call when closing).
    func stopAccessing() {
        if isAccessing, let root = accessRoot {
            root.stopAccessingSecurityScopedResource()
            isAccessing = false
        }
    }

    // MARK: - nidus.json

    var configURL: URL? { vaultURL?.appendingPathComponent("nidus.json") }

    /// The global raw-capture inbox folder (§2.5). Distinct from each project's inbox.
    static let globalInboxFolderName = "_inbox-global"
    /// A folder the user can drop their own icons into; SVGs are picked up by the icon library.
    static let userIconsFolderName = "_icons"

    var userIconsURL: URL? { vaultURL?.appendingPathComponent(Self.userIconsFolderName, isDirectory: true) }

    /// Icon files the user dropped in `_icons/` (SVG/PNG), sorted by name.
    func userIconFiles() -> [URL] {
        guard let dir = userIconsURL,
              let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        let exts: Set<String> = ["svg", "png"]
        return items.filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Reads `nidus.json` if it exists; otherwise creates an empty one and returns it.
    /// Ensures the vault folder and the global inbox exist first.
    @discardableResult
    func ensureConfigExists() throws -> NidusConfig {
        guard let vaultURL, let configURL else { throw VaultError.noBookmarkStored }
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        // Drop the validity marker (idempotent) so this folder is recognizable as a Nidus vault.
        let marker = vaultURL.appendingPathComponent(Self.markerFileName)
        if !FileManager.default.fileExists(atPath: marker.path) {
            try? Data((Self.markerBody + "\n").utf8).write(to: marker, options: .atomic)
        }
        let globalInbox = vaultURL.appendingPathComponent(Self.globalInboxFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: globalInbox, withIntermediateDirectories: true)
        let userIcons = vaultURL.appendingPathComponent(Self.userIconsFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: userIcons, withIntermediateDirectories: true)
        // Canonical, app-owned guide for any AI pointed at this vault — rewritten whenever the shipped
        // content differs (same pattern as the built-in micro-tool seeds), so improvements reach
        // existing vaults too. Never touches user data; it's a distinct file solely for this purpose.
        let agentsGuide = vaultURL.appendingPathComponent(VaultAgentsGuide.fileName)
        let existingGuide = try? String(contentsOf: agentsGuide, encoding: .utf8)
        if existingGuide != VaultAgentsGuide.content {
            try? Data(VaultAgentsGuide.content.utf8).write(to: agentsGuide, options: .atomic)
        }
        if FileManager.default.fileExists(atPath: configURL.path) {
            return try readConfig()
        } else {
            try writeConfig(.empty)
            return .empty
        }
    }

    func readConfig() throws -> NidusConfig {
        guard let configURL else { throw VaultError.noBookmarkStored }
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(NidusConfig.self, from: data)
        } catch {
            throw VaultError.configReadFailed(underlying: error)
        }
    }

    /// Writes `nidus.json` atomically and readably (pretty-printed, sorted keys).
    func writeConfig(_ config: NidusConfig) throws {
        guard let configURL else { throw VaultError.noBookmarkStored }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            throw VaultError.configWriteFailed(underlying: error)
        }
    }

    // MARK: - Folders and project scaffold (Tramo 1)

    /// URL inside the vault from relative components.
    func url(forRelativePath components: String...) -> URL? {
        guard let vaultURL else { return nil }
        return components.reduce(vaultURL) { $0.appendingPathComponent($1) }
    }

    /// Creates a directory (and intermediates) if missing. Only inside the vault.
    func makeDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Creates the project's four `.md` files with their header if they don't exist yet.
    /// Headers are fixed English (universal, parseable). Never overwrites existing files
    /// (doctrine §9.2: only append/create).
    func createProjectScaffold(at projectDir: URL) throws {
        let scaffold: [(file: String, header: String)] = [
            ("inbox.md", "# Inbox\n"),
            ("ideas.md", "# Ideas\n"),
            ("tasks-todo.md", "# Tasks\n"),
            ("tasks-done.md", "# Done\n"),
        ]
        for entry in scaffold {
            let fileURL = projectDir.appendingPathComponent(entry.file)
            guard !FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            try Data(entry.header.utf8).write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Bookmark helpers (see header note)

    private func makeBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [],
                             includingResourceValuesForKeys: nil,
                             relativeTo: nil)
    }

    private func resolveBookmarkData(_ data: Data, isStale: inout Bool) throws -> URL {
        try URL(resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale)
    }
}
