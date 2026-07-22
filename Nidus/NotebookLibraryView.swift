//
//  NotebookLibraryView.swift
//  Nidus
//
//  The Notebook's full library, presented over the workspace. Apple Books-style shelves: the root row
//  (unlabeled) plus one row per group (a real subfolder). Each row scrolls horizontally with big tiles
//  — anchored (pinned) items first — and ends with the classic "+" tile (click → import/create menu,
//  double-click → new note, hover + ⌘V → paste a file or text). A header "Select" toggle enters group
//  editing: check items, then make a group from them or move them. Notes open in the editor; documents
//  in the QuickLook viewer, both full-bleed with a back arrow.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

struct NotebookLibraryView: View {
    let projectFolder: URL?
    let toolName: String
    var startNewNote: Bool = false           // open straight into a fresh note (from the "n" quick action)
    var initialItem: NotebookStore.Item? = nil   // open straight into this item (from a tile click)
    let onClose: () -> Void

    @Environment(NidusModel.self) private var model

    @State private var zones: [NotebookStore.Zone] = []
    @State private var search = ""
    @State private var selectMode = false
    @State private var selection: Set<String> = []       // item ids (url paths)
    @State private var route: Route?

    // Micro-tools are hosted here (not in the editor) so the runner floats over the whole window
    // instead of being clipped to this panel — same reason card tools present it at their top level.
    @State private var microTools: [MicroTool] = []
    @State private var runningTool: MicroTool?
    @State private var showMicroManager = false

    // Group naming / renaming (small popovers)
    @State private var newGroupName = ""
    @State private var showNewGroup = false
    @State private var renamingZone: String?
    @State private var renameDraft = ""

    #if !os(macOS)
    @State private var importingZone: String?
    #endif

    private enum Route: Equatable {
        case note(NotebookStore.Item)
        case newNote(String)     // zone to create in
        case document(NotebookStore.Item)
    }

    var body: some View {
        ZStack {
            if let route {
                routeView(route)
                    .transition(.opacity)
            } else {
                library
                    .transition(.opacity)
            }
        }
        .frame(width: 1040, height: 700)
        .glassCard()
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})
        // Esc steps back one level: from an open note/document → the library grid; from the grid → close.
        .background(Button("", action: escape).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
        // Micro-tools live in the note editor's info column now; only the runner + manager float here
        // (applied AFTER glassCard so they cover the whole window, not clipped to the panel).
        .overlay { microToolRunner }
        .overlay { microToolManagerOverlay }
        .onAppear {
            reload()
            microTools = MicroToolStore.installed(vaultURL: model.vaultURL)
            if startNewNote { route = .newNote("") }
            else if let initialItem { route = initialItem.isNote ? .note(initialItem) : .document(initialItem) }
        }
        .onChange(of: model.fileChangeTick) { reload() }
        .animation(.easeInOut(duration: 0.18), value: route)
        #if !os(macOS)
        .fileImporter(isPresented: Binding(get: { importingZone != nil }, set: { if !$0 { importingZone = nil } }),
                      allowedContentTypes: importUTTypes, allowsMultipleSelection: true) { result in
            let zone = importingZone ?? ""
            importingZone = nil
            if case .success(let urls) = result {
                var added = false
                for u in urls where NotebookStore.importFile(u, into: zone, projectFolder: projectFolder) != nil { added = true }
                if added { reload() }
            }
        }
        #endif
    }

    // MARK: Library screen

    private var library: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            shelves
        }
        .overlay(alignment: .bottom) { if selectMode && !selection.isEmpty { selectionBar } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.pages").font(.title3).foregroundStyle(.secondary)
            Text(toolName.isEmpty ? "Notebook" : toolName)
                .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if !selectMode {
                searchField
            }
            NotebookCircleButton(system: selectMode ? "checkmark" : "checklist",
                                 active: selectMode,
                                 help: selectMode ? "Done selecting" : "Select to group or move") {
                withAnimation(.easeOut(duration: 0.15)) { selectMode.toggle(); selection.removeAll() }
            }
            NotebookCircleButton(system: "xmark", action: onClose)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.tertiary)
            TextField("Search Notebook", text: $search)
                .textFieldStyle(.plain).font(.callout).frame(width: 200)
                .onChange(of: search) { _, v in model.isEditingText = !v.isEmpty }
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private var shelves: some View {
        TidyScroll {
            VStack(alignment: .leading, spacing: 26) {
                let display = displayZones
                if display.allSatisfy({ $0.items.isEmpty }) && !search.isEmpty {
                    ToolEmptyHint("No matches for “\(search)”.").frame(height: 200)
                } else if display.allSatisfy({ $0.items.isEmpty }) && zones.allSatisfy({ $0.items.isEmpty }) {
                    emptyState
                } else {
                    ForEach(display) { zone in shelf(zone) }
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.tertiary)
            Text("Nothing here yet").font(.headline).foregroundStyle(.secondary)
            Text("Write a note or import a document with the + tile below.")
                .font(.callout).foregroundStyle(.tertiary)
            NotebookAddTile(onImport: { importViaPanel("") }, onNewNote: { route = .newNote("") },
                            onPaste: { pasteInto("") }, onDropFiles: { importURLs($0, into: "") })
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity).frame(height: 340)
    }

    private var displayZones: [NotebookStore.Zone] {
        guard !search.isEmpty else { return zones }
        return zones.compactMap { z in
            let items = z.items.filter { NotebookStore.matches($0, query: search) }
            return items.isEmpty ? nil : NotebookStore.Zone(name: z.name, items: items, anchored: z.anchored)
        }
    }

    // MARK: One shelf (a zone)

    @ViewBuilder private func shelf(_ zone: NotebookStore.Zone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(zone.isRoot ? "Main Folder" : zone.name).font(.headline)
                    .foregroundStyle(zone.isRoot ? .secondary : .primary)
                Text("\(zone.items.count)").font(.caption).foregroundStyle(.tertiary)
                // Discreet anchored count (n of max) so pinning has a visible meaning.
                Label("\(zone.anchored.count)/\(NotebookStore.maxAnchors)", systemImage: "pin")
                    .font(.caption2).foregroundStyle(.tertiary).labelStyle(.titleAndIcon)
                    .help("\(zone.anchored.count) of \(NotebookStore.maxAnchors) items pinned to the front")
                Spacer()
                if !zone.isRoot {
                    Menu {
                        Button("Rename group…") { renameDraft = zone.name; renamingZone = zone.name }
                        Button("Ungroup", role: .destructive) { ungroup(zone.name) }
                    } label: {
                        Image(systemName: "ellipsis").font(.callout).foregroundStyle(.secondary)
                            .frame(width: 28, height: 24).contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .popover(isPresented: Binding(get: { renamingZone == zone.name }, set: { if !$0 { renamingZone = nil } })) {
                        renamePopover(zone.name)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(zone.items) { item in
                        NotebookTileView(
                            item: item,
                            anchored: zone.anchored.contains(item.filename),
                            selectMode: selectMode,
                            selected: selection.contains(item.id),
                            onOpen: { open(item) },
                            onToggleSelect: { toggleSelect(item) },
                            onToggleAnchor: { toggleAnchor(item) })
                    }
                    if !selectMode {
                        NotebookAddTile(onImport: { importViaPanel(zone.name) },
                                        onNewNote: { route = .newNote(zone.name) },
                                        onPaste: { pasteInto(zone.name) },
                                        onDropFiles: { importURLs($0, into: zone.name) })
                    }
                }
                // Breathing room so a hover-scaled tile (esp. the leftmost) isn't clipped by the scroll edge.
                .padding(.horizontal, 6).padding(.vertical, 8)
            }
        }
    }

    // MARK: Selection action bar

    private var selectionBar: some View {
        HStack(spacing: 14) {
            Text("\(selection.count) selected").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Divider().frame(height: 18)
            Button { newGroupName = ""; showNewGroup = true } label: {
                Label("New group", systemImage: "folder.badge.plus")
            }
            .popover(isPresented: $showNewGroup) { newGroupPopover }
            Menu {
                Button("Root (no group)") { moveSelection(to: "") }
                ForEach(zones.filter { !$0.isRoot }, id: \.name) { z in
                    Button(z.name) { moveSelection(to: z.name) }
                }
            } label: { Label("Move to", systemImage: "arrow.right.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            Spacer(minLength: 8)
            Button(role: .destructive) { deleteSelection() } label: { Label("Delete", systemImage: "trash") }
        }
        .font(.callout)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.bottom, 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var newGroupPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Name the group").font(.callout.weight(.medium))
            TextField("Group name", text: $newGroupName)
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit(commitNewGroup)
            HStack {
                Spacer()
                Button("Create", action: commitNewGroup).keyboardShortcut(.defaultAction)
                    .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }

    private func renamePopover(_ zone: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename group").font(.callout.weight(.medium))
            TextField("Group name", text: $renameDraft)
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit { commitRename(zone) }
            HStack { Spacer(); Button("Rename") { commitRename(zone) }.keyboardShortcut(.defaultAction) }
        }
        .padding(14)
    }

    // MARK: Routed screens (editor / viewer)

    @ViewBuilder private func routeView(_ route: Route) -> some View {
        switch route {
        case .note(let item):
            NotebookNoteEditor(item: item, newZone: nil, projectFolder: projectFolder,
                               microTools: microTools, onRunTool: { runningTool = $0 },
                               onManageTools: { showMicroManager = true }) { back() }
        case .newNote(let zone):
            NotebookNoteEditor(item: nil, newZone: zone, projectFolder: projectFolder,
                               microTools: microTools, onRunTool: { runningTool = $0 },
                               onManageTools: { showMicroManager = true }) { back() }
        case .document(let item):
            NotebookDocumentView(item: item, toolName: toolName, projectFolder: projectFolder) { back() }
        }
    }

    // MARK: Micro-tools (runner + manager float over the whole window)

    @ViewBuilder private var microToolRunner: some View {
        if let tool = runningTool {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).frame(width: 5000, height: 5000)
                    .onTapGesture { runningTool = nil }
                MicroToolRunnerView(tool: tool) { runningTool = nil }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var microToolManagerOverlay: some View {
        if showMicroManager {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).frame(width: 5000, height: 5000)
                    .onTapGesture { showMicroManager = false }
                MicroToolManager(tools: microTools,
                                 onImport: { showMicroManager = false; importMicroTool() },
                                 onDelete: { tool in
                                     MicroToolStore.uninstall(tool)
                                     microTools = MicroToolStore.installed(vaultURL: model.vaultURL)
                                 })
            }
            .transition(.opacity)
        }
    }

    private func importMicroTool() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.javaScript]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            _ = MicroToolStore.install(from: url, vaultURL: model.vaultURL)
            microTools = MicroToolStore.installed(vaultURL: model.vaultURL)
        }
        #endif
    }

    private func back() {
        withAnimation(.easeInOut(duration: 0.18)) { route = nil }
        reload()
    }

    /// Esc behaviour: inside a note/document, go back to the library; on the library grid, close.
    private func escape() {
        if route != nil { back() } else { onClose() }
    }

    // MARK: Actions

    private func reload() {
        zones = NotebookStore.load(projectFolder: projectFolder)
        // Drop selections whose items vanished.
        let ids = Set(zones.flatMap { $0.items.map(\.id) })
        selection = selection.intersection(ids)
    }

    private func open(_ item: NotebookStore.Item) {
        if selectMode { toggleSelect(item); return }
        withAnimation(.easeInOut(duration: 0.18)) {
            route = item.isNote ? .note(item) : .document(item)
        }
    }

    private func toggleSelect(_ item: NotebookStore.Item) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    private func toggleAnchor(_ item: NotebookStore.Item) {
        NotebookStore.toggleAnchor(item, projectFolder: projectFolder)
        Haptics.tap()
        reload()
    }

    private var selectedItems: [NotebookStore.Item] {
        zones.flatMap { $0.items }.filter { selection.contains($0.id) }
    }

    private func deleteSelection() {
        for item in selectedItems { NotebookStore.delete(item, projectFolder: projectFolder) }
        selection.removeAll()
        reload()
    }

    private func moveSelection(to zone: String) {
        NotebookStore.move(selectedItems, toZone: zone, projectFolder: projectFolder)
        selection.removeAll()
        reload()
    }

    private func commitNewGroup() {
        let name = NotebookStore.uniqueZoneName(newGroupName, projectFolder: projectFolder)
        NotebookStore.move(selectedItems, toZone: name, projectFolder: projectFolder)
        showNewGroup = false
        selection.removeAll()
        selectMode = false
        reload()
    }

    private func commitRename(_ zone: String) {
        NotebookStore.renameZone(zone, to: renameDraft, projectFolder: projectFolder)
        renamingZone = nil
        reload()
    }

    private func ungroup(_ zone: String) {
        NotebookStore.ungroup(zone, projectFolder: projectFolder)
        reload()
    }

    // MARK: Add flow (import / create / paste)

    private func importViaPanel(_ zone: String) {
        #if os(macOS)
        // NSOpenPanel (not SwiftUI's `.fileImporter`) — its completion doesn't fire reliably for views
        // presented inside the WorkspaceOverlay's AnyView (same reason micro-tool import uses it).
        let panel = NSOpenPanel()
        panel.allowedContentTypes = importUTTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { resp in
            guard resp == .OK else { return }
            var added = false
            for u in panel.urls where NotebookStore.importFile(u, into: zone, projectFolder: projectFolder) != nil { added = true }
            if added { reload() }
        }
        #else
        importingZone = zone
        #endif
    }

    private func importURLs(_ urls: [URL], into zone: String) {
        var added = false
        for u in urls where NotebookStore.importFile(u, into: zone, projectFolder: projectFolder) != nil { added = true }
        if added { Haptics.tap(); reload() }
    }

    private func pasteInto(_ zone: String) {
        #if os(macOS)
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            var added = false
            for u in urls where NotebookStore.importableExtensions.contains(u.pathExtension.lowercased()) {
                if NotebookStore.importFile(u, into: zone, projectFolder: projectFolder) != nil { added = true }
            }
            if added { Haptics.tap(); reload(); return }
        }
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let item = NotebookStore.createNoteFromText(s, in: zone, projectFolder: projectFolder) {
                reload()
                withAnimation(.easeInOut(duration: 0.18)) { route = .note(item) }
            }
        }
        #endif
    }

    private var importUTTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .rtf]
        for ext in ["md", "markdown", "docx", "odt", "pages"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }
}
