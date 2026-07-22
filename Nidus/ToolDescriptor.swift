//
//  ToolDescriptor.swift
//  Nidus
//
//  Tool architecture (Blueprint §3.6, GUI workspace §0/§6).
//  A tool is a native SwiftUI module that declares: identifier, valid sizes, the .md file(s)
//  it touches (Markdown, never opaque), and its view. Each tool lives in its own file with a
//  `static let descriptor`; the registry assembles them from one list, so adding/importing a
//  new tool is: new file + one line in `all`.
//

import SwiftUI

/// What a tool needs to render and to reach its files inside the project folder.
/// `fileMap` maps a tool's DECLARED filename to this instance's RESOLVED filename, so two
/// instances of the same tool (e.g. two "Ideas") read/write different `.md` files.
struct ToolContext {
    let size: ToolSize
    let projectRef: ProjectRef
    /// The project's folder in the vault; the tool reads/writes its `.md` here.
    let folderURL: URL?
    /// declared filename → resolved filename for this instance.
    var fileMap: [String: String] = [:]
    /// This instance's display name (e.g. a renamed "Recipes"), for headers.
    var name: String = ""
    /// This instance's stable slot id, so search can reveal a card in the right instance.
    var slotID: String = ""

    /// Absolute URL of one of the tool's declared files (mapped to this instance's file).
    func fileURL(_ declared: String) -> URL? {
        folderURL?.appendingPathComponent(fileMap[declared] ?? declared)
    }
}

/// The behavioural family of a tool — drives drag compatibility and role (guideline §3). Public
/// classes for third-party tools: collector, worker, lens, widget. `archive` is the built-in sink.
enum ToolClass {
    case collector  // neutral card store (Inbox, Ideas)
    case worker     // collector + own schema + actions (Task Manager)
    case lens       // read-only projection of a worker (Calendar) — not a drop target
    case widget     // display/utility, no card flow, may have no .md (Pomodoro…)
    case archive    // system singleton sink: completed items, with origin memory
}

/// What a card "is", for drag enrichment/compatibility. Universal content is `.generic`; a Worker
/// can mint a richer kind (e.g. `.task`). Kept minimal until the card model lands (step 3).
enum CardKind: String { case generic, task }

/// A tool-specific operation surfaced in its UI (e.g. Task Manager's "complete"). Declared here so
/// the contract is complete; behaviour is wired in later steps.
struct ToolAction: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let icon: String
}

/// The hotkey-driven quick capture a tool exposes (press the letter → add to this tool). The
/// descriptor holds the DEFAULT; the user can override the hotkey per instance (step 2).
struct ToolQuickAction {
    let defaultHotkey: Character
    let label: LocalizedStringKey
    /// How a quick-captured string is appended to this tool's file (idea-style / task-style).
    let kind: QuickAddKind
}

/// Declarative description of a tool. `makeView` produces its body for a given context/size.
/// All display info (name, description, sizes) lives here — the library reads it, never hardcodes.
struct ToolDescriptor: Identifiable {
    let id: String
    let title: LocalizedStringKey
    /// Plain-string default name for new instances, the library and the in-file metadata header.
    let defaultName: String
    /// One line on what the tool is for (shown in the library).
    let summary: LocalizedStringKey
    let icon: String
    /// Sizes the tool's UI renders well in (subset of the three allowed).
    let validSizes: Set<ToolSize>
    /// Relative `.md` filenames the tool reads/writes (the file contract).
    let files: [String]
    /// Whether the user can have more than one instance (Inbox is the singleton mother tool).
    let allowsMultiple: Bool
    /// Behavioural family — drives drag compatibility and role (guideline §3).
    let toolClass: ToolClass
    /// Card kinds accepted by drag, and the kind this tool mints. Lossless regardless: unknown
    /// metadata is always preserved (guideline §2). Defaults suit a neutral collector.
    var accepts: Set<CardKind> = [.generic]
    var produces: CardKind = .generic
    /// Tool-specific actions (e.g. "complete"). Wired in later steps.
    var actions: [ToolAction] = []
    /// Optional hotkey-driven quick capture (default; overridable per instance in step 2).
    var quickAction: ToolQuickAction? = nil
    /// The tool's content view for the tile body.
    let makeView: (ToolContext) -> AnyView

    /// Valid sizes in canonical order, for display.
    var sizesInOrder: [ToolSize] { ToolSize.allCases.filter { validSizes.contains($0) } }
}

/// Registry of available tools. The four base tools come with the app; new tools register by
/// adding their `static let descriptor` to `all` (custom tools are post-MVP, Blueprint §9 TF-1).
enum ToolRegistry {
    /// The native tools shipped with the app — curated, non-deletable.
    static let builtIn: [ToolDescriptor] = [
        InboxToolView.descriptor,
        IdeasToolView.descriptor,
        TaskManagerToolView.descriptor,
        TaskArchiveToolView.descriptor,
        ReferenceBoardToolView.descriptor,
        EventLogToolView.descriptor,
        NotebookToolView.descriptor,
    ]

    /// Installed (`.js`) tools, refreshed from the vault's `_tools/` on vault open / import / delete.
    /// nonisolated(unsafe): only ever written from the main actor (NidusModel).
    nonisolated(unsafe) private static var installedDescriptors: [ToolDescriptor] = []

    /// Replace the installed set (call after loading `_tools/`).
    static func setInstalled(_ tools: [InstalledTool]) {
        installedDescriptors = tools.map(InstalledToolEngine.descriptor)
    }

    static var all: [ToolDescriptor] { builtIn + installedDescriptors }

    private static let builtInByID: [String: ToolDescriptor] =
        Dictionary(uniqueKeysWithValues: builtIn.map { ($0.id, $0) })

    static func descriptor(for id: String) -> ToolDescriptor {
        builtInByID[id] ?? installedDescriptors.first { $0.id == id } ?? ToolDescriptor(
            id: id,
            title: LocalizedStringKey(id),
            defaultName: id,
            summary: "Unknown tool",
            icon: "square.grid.2x2",
            validSizes: [.small, .medium, .large],
            files: [],
            allowsMultiple: true,
            toolClass: .collector,
            makeView: { _ in AnyView(ToolEmptyHint("Unknown tool")) }
        )
    }
}
