//
//  NidusConfig.swift
//  Nidus
//
//  Codable model of `nidus.json` (Blueprint v0.6 §2.2).
//  The single structured-state file. Lives at the vault root, readable without Nidus.
//

import Foundation

/// Mirror of `nidus.json`. The truth remains the file on disk; this type only (de)serializes it.
struct NidusConfig: Codable, Equatable, Sendable {
    var version: String
    var disciplines: [Discipline]
    /// Vault-wide bank of task tags (shared by every Task Manager). Added in the task tramo.
    var tags: [TaskTag]
    /// Ordered project ids pinned to the top of the sidebar (global, max 3). Focus aid.
    var pinnedProjects: [String]

    static let currentVersion = "1"
    static let empty = NidusConfig(version: currentVersion, disciplines: [], tags: [])
    static let maxPinned = 3

    init(version: String, disciplines: [Discipline], tags: [TaskTag] = [], pinnedProjects: [String] = []) {
        self.version = version; self.disciplines = disciplines; self.tags = tags
        self.pinnedProjects = pinnedProjects
    }

    enum CodingKeys: String, CodingKey {
        case version, disciplines, tags
        case pinnedProjects = "pinned_projects"
    }

    // Tolerant decode: older nidus.json files have no `tags` / `pinned_projects` key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        disciplines = try c.decode([Discipline].self, forKey: .disciplines)
        tags = try c.decodeIfPresent([TaskTag].self, forKey: .tags) ?? []
        pinnedProjects = try c.decodeIfPresent([String].self, forKey: .pinnedProjects) ?? []
    }
}

/// A discipline = a folder inside the vault grouping projects (ceramics, programming…).
struct Discipline: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var folder: String
    var cover: DisciplineCover?
    var projects: [Project]
}

/// A project within a discipline. `folder` is relative to its discipline's folder.
struct Project: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var folder: String
    var description: String?
    var icon: String?
    var linkedLocation: LinkedLocation?
    var layout: ProjectLayout?
    /// Up to 3 user shortcuts shown on the project card (open an app, a URL, or a file/folder).
    var quickActions: [QuickAction]?
    /// Lifecycle tag: nil/"active" | "completed" | "archived" | "deprecated". Internal (not a folder).
    var status: String?
    /// If this project is a fork, points at the project it was forked from.
    var forkedFrom: ProjectFork?

    enum CodingKeys: String, CodingKey {
        case id, name, folder, description, icon, layout, status
        case linkedLocation = "linked_location"
        case quickActions = "quick_actions"
        case forkedFrom = "forked_from"
    }

    static let defaultIcon = "circle.grid.2x2"
}

/// A pointer back to the project a fork came from (a "Forked Original" quick action opens it).
struct ProjectFork: Codable, Equatable, Sendable {
    var disciplineID: String
    var projectID: String

    enum CodingKeys: String, CodingKey {
        case disciplineID = "discipline_id"
        case projectID = "project_id"
    }
}

/// A user-defined shortcut on the project card: opens an app, a web URL, or a file/folder.
struct QuickAction: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var kind: Kind
    /// File-system path for `.app`/`.file`, or a URL string for `.web`.
    var target: String

    enum Kind: String, Codable, Sendable { case app, web, route, script }
}

/// Discipline cover for the home spheres (§2.7). Default: a dynamic glass sphere with an icon.
struct DisciplineCover: Codable, Equatable, Sendable {
    var type: String   // e.g. "dynamic-sphere"
    var icon: String   // SF Symbol name
    var tint: String   // hex color, e.g. "#3A5BFF"

    static func makeDefault() -> DisciplineCover {
        DisciplineCover(type: "dynamic-sphere", icon: "circle.hexagongrid", tint: "#3A5BFF")
    }
}

/// Device-aware pointer to the project's physical working folder (§2.3).
/// `null` in JSON when the project is pure thinking/tasks.
struct LinkedLocation: Codable, Equatable, Sendable {
    var deviceId: String
    var deviceName: String
    var path: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case path
    }
}

/// The project's workspace layout: which overview tool and which tools occupy the 5×2 grid (§3).
/// Persisted now (Tramo 1); the grid is rendered in Tramo 2.
struct ProjectLayout: Codable, Equatable, Sendable {
    var overviewTool: String
    var grid: [ToolSlot]
    /// Instances removed from the board but kept (their `.md` data persists). They reappear in
    /// the library's "Project tools" section to be re-attached, instead of creating duplicates.
    var detached: [ToolSlot]?

    enum CodingKeys: String, CodingKey {
        case overviewTool = "overview_tool"
        case grid
        case detached
    }

    /// Default skeleton every project is born with: the four base tools.
    static func makeDefault() -> ProjectLayout {
        ProjectLayout(
            overviewTool: "deadline-calendar",
            grid: [
                ToolSlot(id: "inbox", tool: "inbox", size: "1x2", col: 0, row: 0),
                ToolSlot(id: "ideas", tool: "ideas", size: "1x2", col: 1, row: 0),
                ToolSlot(id: "task-manager", tool: "task-manager", size: "1x2", col: 2, row: 0),
                ToolSlot(id: "task-archive", tool: "task-archive", size: "1x2", col: 3, row: 0),
            ]
        )
    }
}

/// One tool INSTANCE placed in the grid. A stable `id` (so it can move), the tool `type`, an
/// optional custom `name`, the resolved `.md` filenames this instance owns, plus size/position.
struct ToolSlot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var tool: String
    var name: String?
    var size: String   // "1x1" | "1x2" | "2x2"
    var col: Int
    var row: Int
    /// Resolved `.md` basenames, parallel to the tool's declared files. nil = use the tool's
    /// canonical files (the default singleton instances).
    var files: [String]?
    /// Per-instance quick-add hotkey override (one letter). nil = use the descriptor's default.
    var hotkey: String?

    init(id: String, tool: String, name: String? = nil, size: String, col: Int, row: Int,
         files: [String]? = nil, hotkey: String? = nil) {
        self.id = id; self.tool = tool; self.name = name
        self.size = size; self.col = col; self.row = row; self.files = files; self.hotkey = hotkey
    }

    enum CodingKeys: String, CodingKey { case id, tool, name, size, col, row, files, hotkey }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tool = try c.decode(String.self, forKey: .tool)
        size = try c.decode(String.self, forKey: .size)
        col = try c.decode(Int.self, forKey: .col)
        row = try c.decode(Int.self, forKey: .row)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        files = try c.decodeIfPresent([String].self, forKey: .files)
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey)
        // Tolerate older configs without a stored id.
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "\(tool)-\(col)-\(row)"
    }
}
