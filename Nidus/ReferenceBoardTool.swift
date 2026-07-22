//
//  ReferenceBoardTool.swift
//  Nidus
//
//  Reference Board (mood board) — image-first. Source of truth: a real `Nidus References` folder in
//  the project's linked folder (see ReferenceStore). The tile shows a masonry collage of the first
//  images that fit; double-clicking opens the big viewer (browse + sort + reorder + add).
//

import SwiftUI
import UniformTypeIdentifiers

/// Collage density (bigger cells = fewer, larger images).
enum BoardDensity: String, CaseIterable, Identifiable {
    case small, medium
    var id: String { rawValue }
    var label: String { self == .small ? "Small" : "Medium" }
    /// Minimum column width for the tile's auto-fill (small lets images shrink more → more fit).
    var tileColumnPixels: CGFloat { self == .small ? 92 : 132 }
    var viewerColumnPixels: CGFloat { self == .small ? 150 : 200 }
}

struct ReferenceBoardToolView: View {
    @Environment(NidusModel.self) private var model
    @Environment(WorkspaceOverlay.self) private var overlay
    let context: ToolContext

    @State private var rawItems: [ReferenceStore.Item] = []
    @State private var manifest = ReferenceStore.Manifest(id: "", order: [], arrival: [:])

    @AppStorage private var densityRaw: String
    @AppStorage private var sortRaw: String

    init(context: ToolContext) {
        self.context = context
        let s = context.slotID
        _densityRaw = AppStorage(wrappedValue: BoardDensity.small.rawValue, "nidus.refboard.density.\(s)")
        _sortRaw = AppStorage(wrappedValue: RefSort.arrival.rawValue, "nidus.refboard.sort.\(s)")
    }

    // The board lives inside the project's OWN vault folder (next to the Notebook and `_assets/`), so
    // it works for every project and syncs like everything else. Resolved per-instance via `fileURL`
    // so duplicated boards each get their own folder ("Nidus References", "Nidus References-2", …).
    private var folder: URL? { context.fileURL(ReferenceStore.folderName) }
    private var density: BoardDensity { BoardDensity(rawValue: densityRaw) ?? .small }
    private var sort: RefSort { RefSort(rawValue: sortRaw) ?? .arrival }
    private var items: [ReferenceStore.Item] {
        ReferenceStore.sorted(rawItems, manifest, mode: sort)
    }

    var body: some View {
        Group {
            if let folder {
                content(folder)
            } else {
                ToolEmptyHint("No project folder.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reload() }
        .onChange(of: model.fileChangeTick) { reload() }
    }

    private func content(_ folder: URL) -> some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                MasonryTile(items: items, colPixels: density.tileColumnPixels)
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(rawItems.count) image\(rawItems.count == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .padding(6)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // A click anywhere on the tile opens the viewer (nothing else here to conflict). simultaneous
        // so it coexists with the scroll of the collage below.
        .simultaneousGesture(TapGesture().onEnded { openViewer(folder) })
        .dropDestination(for: URL.self) { urls, _ in addFiles(urls, folder); return true }
        .focusable()
        .focusEffectDisabled()
        .onImagePaste { paste(folder) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled").font(.title2).foregroundStyle(.secondary)
            Text("Paste or drop images").font(.callout).foregroundStyle(.secondary)
            Text("Double-click to open and add from files").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func reload() {
        guard let folder else { rawItems = []; return }
        // Read-only: do NOT ensure() here. Creating the folder just to LOOK at it means a project whose
        // folder was just deleted gets its "Nidus References" folder re-created by this reload during the
        // delete's file-change notification — leaving an orphan on disk. The folder is created lazily on
        // the first paste/import (those still ensure). `reconcile` is tolerant of a missing folder.
        let r = ReferenceStore.reconcile(folder)
        rawItems = r.items
        manifest = r.manifest
    }

    private func addFiles(_ urls: [URL], _ folder: URL) {
        guard let dir = ReferenceStore.ensure(folder) else { return }
        for u in urls { _ = ReferenceStore.importFile(u, into: dir) }
        model.notifyFileChange()
    }

    private func paste(_ folder: URL) {
        guard let dir = ReferenceStore.ensure(folder) else { return }
        var added = false
        if let png = ReferenceStore.clipboardImagePNG(),
           ReferenceStore.saveData(png, ext: "png", into: dir) != nil { added = true }
        for u in ReferenceStore.clipboardImageURLs() where ReferenceStore.importFile(u, into: dir) != nil {
            added = true
        }
        if added { model.notifyFileChange() }
    }

    private func openViewer(_ folder: URL) {
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                ReferenceViewer(folder: folder,
                                toolIcon: ReferenceBoardToolView.descriptor.icon,
                                toolName: context.name.isEmpty ? "Reference Board" : context.name,
                                densityRaw: $densityRaw, sortRaw: $sortRaw) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }
}

// MARK: - Masonry (fixed-width columns, variable heights, no cropping)

/// The tile's masonry: ALL images, columns from the density. Overflow is scrollable (no scrollbar);
/// anchored to the top so the first (highest-priority) images are always what you see on open.
private struct MasonryTile: View {
    let items: [ReferenceStore.Item]
    let colPixels: CGFloat   // column width (from density)

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let cols = max(2, Int(geo.size.width / colPixels))
            let colW = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let columns = distribute(items, cols: cols, colW: colW, spacing: spacing, maxHeight: nil)
            ScrollView {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { c in
                        VStack(spacing: spacing) {
                            ForEach(columns[c]) { BoardThumb(item: $0, width: colW) }
                        }
                        .frame(width: colW, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
        }
    }
}

/// Scrollable masonry for the viewer: all images, hover-zoom, per-image note on hover.
private struct MasonryScroll: View {
    let items: [ReferenceStore.Item]
    let colPixels: CGFloat
    var notes: [String: String] = [:]
    var onSetNote: (String, String) -> Void = { _, _ in }
    var onHoverItem: (ReferenceStore.Item?) -> Void = { _ in }   // report the hovered image up (for Quick Look)
    @State private var hoveredID: String?

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let hInset: CGFloat = 26, vInset: CGFloat = 20
            // Columns fit inside the inset area, so images (even hover-zoomed) never reach the edges.
            let available = max(1, geo.size.width - hInset * 2)
            let cols = max(2, Int(available / colPixels))
            let colW = (available - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let columns = distribute(items, cols: cols, colW: colW, spacing: spacing, maxHeight: nil)
            ScrollView {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { c in
                        VStack(spacing: spacing) {
                            ForEach(columns[c]) { item in
                                BoardThumb(item: item, width: colW, hoverZoom: true,
                                           note: notes[item.name] ?? "",
                                           onSetNote: { onSetNote(item.name, $0) },
                                           onHoverChanged: { over in
                                               hoveredID = over ? item.id : (hoveredID == item.id ? nil : hoveredID)
                                               if over { onHoverItem(item) } else if hoveredID == nil { onHoverItem(nil) }
                                           })
                            }
                        }
                        .frame(width: colW, alignment: .top)
                        // Raise the whole column when it holds the hovered image, so the enlarged
                        // photo sits on top of neighbours in OTHER columns too (not just its own).
                        .zIndex(columns[c].contains { $0.id == hoveredID } ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, hInset).padding(.vertical, vInset)
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
        }
    }
}

/// Greedy masonry: each image (in order) to the shortest column. `maxHeight` (tile) stops at the
/// first that wouldn't fully fit; nil (viewer) places them all.
private func distribute(_ items: [ReferenceStore.Item], cols: Int, colW: CGFloat,
                        spacing: CGFloat, maxHeight: CGFloat?) -> [[ReferenceStore.Item]] {
    var heights = [CGFloat](repeating: 0, count: cols)
    var out = [[ReferenceStore.Item]](repeating: [], count: cols)
    for item in items {
        let h = colW / max(item.aspectRatio, 0.25)
        let c = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
        let add = (out[c].isEmpty ? 0 : spacing) + h
        if let maxHeight, heights[c] + add > maxHeight { break }
        out[c].append(item)
        heights[c] += add
    }
    return out
}

/// One collage cell — a cached, downsampled thumbnail sized to the image's exact ratio (no crop).
/// The cache means re-measuring/re-laying-out never reloads (fixes the flicker).
private struct BoardThumb: View {
    let item: ReferenceStore.Item
    let width: CGFloat
    var hoverZoom: Bool = false
    var note: String = ""
    var onSetNote: ((String) -> Void)? = nil
    var onHoverChanged: ((Bool) -> Void)? = nil

    @State private var image: Image?
    @State private var hover = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var canNote: Bool { onSetNote != nil }
    private var display: Image? {
        if let image { return image }
        if let cg = ThumbnailCache.shared.cached(item.url) { return Image(decorative: cg, scale: 1) }
        return nil
    }

    var body: some View {
        Group {
            if let display { display.resizable().aspectRatio(contentMode: .fill) }
            else { Color.primary.opacity(0.06) }
        }
        .frame(width: width, height: width / max(item.aspectRatio, 0.25))
        .overlay(alignment: .bottom) { noteOverlay }
        .overlay(alignment: .bottomTrailing) {
            if canNote && hover && !editing && note.isEmpty {
                Image(systemName: "text.bubble").font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                    .padding(4).background(Circle().fill(.black.opacity(0.4))).padding(5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .scaleEffect(hoverZoom && hover ? 1.15 : 1)
        .zIndex(hover || editing ? 1 : 0)
        .shadow(color: .black.opacity((hoverZoom && hover) || editing ? 0.25 : 0), radius: 10, y: 4)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h }; onHoverChanged?(h) }
        .onTapGesture(count: 2) { if canNote { beginEdit() } }
        .task(id: item.url) {
            if ThumbnailCache.shared.cached(item.url) != nil { return }
            let box = await Task.detached(priority: .utility) { () -> SendableCGImage? in
                ReferenceStore.loadThumbnailCG(item.url, maxPixel: 600).map(SendableCGImage.init)
            }.value
            if let box { ThumbnailCache.shared.store(box.cg, item.url); image = Image(decorative: box.cg, scale: 1) }
        }
    }

    /// Soft whitish translucent note — shown on hover; editable (double-click). Why is it here?
    @ViewBuilder private var noteOverlay: some View {
        if editing {
            // Wraps within the cell (like the display) instead of scrolling horizontally. Enter saves.
            TextField("Why is it here?", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.caption).foregroundStyle(noteTextColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(1...3)
                .focused($focused)
                .onChange(of: draft) {
                    if draft.contains("\n") { draft = draft.replacingOccurrences(of: "\n", with: ""); commit() }
                    else if draft.count > 60 { draft = String(draft.prefix(60)) }
                }
                .onChange(of: focused) { if !focused { commit() } }
                .padding(.horizontal, 10).padding(.top, 22).padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(noteGradient(0.92))
        } else if canNote && hover && !note.isEmpty {
            Text(note)
                .font(.caption).foregroundStyle(noteTextColor.opacity(0.72))
                .lineLimit(3).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 10).padding(.top, 24).padding(.bottom, 8)
                .background(noteGradient(0.9))
                .transition(.opacity)
        }
    }

    /// White scrim + near-black text in light mode reads fine, but in dark mode a white scrim washes
    /// out and white-on-white text disappears — so the scrim itself flips to a dark tint there instead.
    private var noteTextColor: Color { colorScheme == .dark ? .white : .black }
    private var noteScrimColor: Color { colorScheme == .dark ? .black : .white }

    /// A SOLID translucent zone at the bottom (legible text) that only starts fading past the midpoint,
    /// all the way to fully transparent at the top (no hard edge).
    private func noteGradient(_ solid: Double) -> some View {
        LinearGradient(stops: [
            .init(color: noteScrimColor.opacity(solid), location: 0.0),
            .init(color: noteScrimColor.opacity(solid), location: 0.58),
            .init(color: noteScrimColor.opacity(0), location: 1.0),
        ], startPoint: .bottom, endPoint: .top)
    }

    private func beginEdit() { draft = note; editing = true; focused = true }
    private func commit() { onSetNote?(draft); editing = false }
}

// MARK: - Quick Look (Space to enlarge a hovered image, in-app)

/// A full-size, in-app preview of one image over a dark scrim — like macOS Quick Look. Loads the full
/// file (not the thumbnail) so details are crisp; a click anywhere closes it.
private struct QuickLookOverlay: View {
    let item: ReferenceStore.Item
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.62)).ignoresSafeArea()
            if let img = nidusLoadImage(at: item.url) {
                img.resizable().scaledToFit()
                    .padding(28)
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
    }
}

// MARK: - Big viewer (browse + sort + reorder + add)

private struct ReferenceViewer: View {
    @Environment(NidusModel.self) private var model
    let folder: URL
    let toolIcon: String
    let toolName: String
    @Binding var densityRaw: String
    @Binding var sortRaw: String
    let onClose: () -> Void

    @State private var rawItems: [ReferenceStore.Item] = []
    @State private var manifest = ReferenceStore.Manifest(id: "", order: [], arrival: [:])
    @State private var editing = false
    @State private var importing = false
    @State private var reorderHover = false
    @State private var hoveredItem: ReferenceStore.Item?   // the image under the cursor (for Quick Look)
    @State private var quickLook: ReferenceStore.Item?     // the image blown up full-size, nil = closed
    @FocusState private var focused: Bool

    private var density: BoardDensity { BoardDensity(rawValue: densityRaw) ?? .small }
    private var sort: RefSort { RefSort(rawValue: sortRaw) ?? .arrival }
    private var items: [ReferenceStore.Item] {
        ReferenceStore.sorted(rawItems, manifest, mode: sort)
    }
    private var manualItems: [ReferenceStore.Item] {
        ReferenceStore.sorted(rawItems, manifest, mode: .manual)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            toolbar
            Divider().opacity(0.4)
            Group {
                if rawItems.isEmpty { emptyState }
                else if editing {
                    ReorderView(items: manualItems,
                                onCommit: { names in
                                    ReferenceStore.saveOrder(names, folder)
                                    sortRaw = RefSort.manual.rawValue
                                    model.notifyFileChange()
                                },
                                onDelete: { delete($0) })
                }
                else {
                    MasonryScroll(items: items, colPixels: density.viewerColumnPixels,
                                  notes: manifest.notes,
                                  onSetNote: { name, note in setNote(name, note) },
                                  onHoverItem: { hoveredItem = $0 })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if !rawItems.isEmpty && !editing {
                    VStack(spacing: 8) {
                        AddFab { importing = true }
                        Text("Did you know you can paste (⌘V) or drag any image straight in?")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 920, height: 640)
        .glassCard()
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})   // swallow empty-chrome taps (no fall-through dismiss)
        .background(Button("", action: close).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
        .focusable().focusEffectDisabled().focused($focused)
        // Quick Look: hover an image, tap Space to blow it up full-size; Space (or a click) closes it.
        .onKeyPress(.space) {
            if quickLook != nil { quickLook = nil; return .handled }
            if let hoveredItem { quickLook = hoveredItem; return .handled }
            return .ignored
        }
        .overlay {
            if let ql = quickLook {
                QuickLookOverlay(item: ql) { quickLook = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: quickLook?.id)
        .onAppear { focused = true; reload() }
        .onChange(of: model.fileChangeTick) { reload() }
        .onImagePaste { paste() }
        .dropDestination(for: URL.self) { urls, _ in addFiles(urls); return true }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { addFiles(urls) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: toolIcon).font(.title3).foregroundStyle(.secondary)
            Text(toolName).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text("\(rawItems.count) image\(rawItems.count == 1 ? "" : "s")")
                .font(.callout).foregroundStyle(.tertiary)
            circleButton("xmark", action: close)
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 10)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Sort — grouped + labelled so the options read as one discreet control.
            HStack(spacing: 8) {
                Text("Sort").font(.caption2.weight(.medium)).foregroundStyle(.tertiary).fixedSize()
                Picker("", selection: Binding(get: { sort }, set: { sortRaw = $0.rawValue })) {
                    ForEach(RefSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .fixedSize()
            .disabled(editing).opacity(editing ? 0.4 : 1)

            // Density — pictographic (more/smaller vs fewer/bigger).
            Picker("", selection: Binding(get: { density }, set: { densityRaw = $0.rawValue })) {
                Image(systemName: "square.grid.3x3").tag(BoardDensity.small)
                Image(systemName: "square.grid.2x2").tag(BoardDensity.medium)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            .help("Image size")

            Spacer()

            AddPill(onImport: { importing = true }, onPaste: { paste() })

            Button { withAnimation(.easeOut(duration: 0.15)) { editing.toggle() } } label: {
                Label(editing ? "Done" : "Reorder", systemImage: editing ? "checkmark" : "arrow.up.arrow.down")
                    .font(.callout.weight(.medium)).foregroundStyle(editing ? Color.accentColor : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(reorderHover && !editing ? 0.08 : 0)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(reorderHover ? 0.28 : 0.14)))
            }
            .buttonStyle(.plain)
            .onHover { reorderHover = $0 }
            .animation(.easeOut(duration: 0.15), value: reorderHover)
        }
        .padding(.horizontal, 22).padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled").font(.largeTitle).foregroundStyle(.secondary)
            Text("Paste, drop or import images").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func circleButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30).background(Circle().fill(Color.primary.opacity(0.07)))
        }.buttonStyle(.plain)
    }

    // MARK: Actions

    private func reload() {
        let r = ReferenceStore.reconcile(folder)
        rawItems = r.items
        manifest = r.manifest
    }

    private func addFiles(_ urls: [URL]) {
        guard let dir = ReferenceStore.ensure(folder) else { return }
        for u in urls { _ = ReferenceStore.importFile(u, into: dir) }
        model.notifyFileChange()
    }

    private func paste() {
        guard let dir = ReferenceStore.ensure(folder) else { return }
        var added = false
        if let png = ReferenceStore.clipboardImagePNG(),
           ReferenceStore.saveData(png, ext: "png", into: dir) != nil { added = true }
        for u in ReferenceStore.clipboardImageURLs() where ReferenceStore.importFile(u, into: dir) != nil {
            added = true
        }
        if added { model.notifyFileChange() }
    }

    private func delete(_ item: ReferenceStore.Item) {
        ReferenceStore.delete(item.url)
        model.notifyFileChange()
    }

    private func setNote(_ name: String, _ note: String) {
        ReferenceStore.setNote(note, for: name, in: folder)
        model.notifyFileChange()
    }

    // Escape (and the ⌘-cancel button) closes the Quick Look first if it's open, else the whole viewer.
    private func close() {
        if quickLook != nil { quickLook = nil } else { onClose() }
    }
}

/// Grid reorder that actually works: the SAME proven pattern as the card drag — a floating copy
/// follows the cursor over a STATIC grid (frames reported once, so no churn/warning), the target
/// cell highlights, and a SINGLE move happens on release (no live re-indexing = no lag/jank).
private struct ReorderView: View {
    let items: [ReferenceStore.Item]
    let onCommit: ([String]) -> Void
    let onDelete: (ReferenceStore.Item) -> Void

    @State private var order: [ReferenceStore.Item]
    @State private var dragID: String?
    @State private var dragLocation: CGPoint = .zero
    @State private var frames: [String: CGRect] = [:]

    init(items: [ReferenceStore.Item], onCommit: @escaping ([String]) -> Void,
         onDelete: @escaping (ReferenceStore.Item) -> Void) {
        self.items = items; self.onCommit = onCommit; self.onDelete = onDelete
        _order = State(initialValue: items)
    }

    private var targetID: String? { dragID == nil ? nil : nearestID(to: dragLocation) }

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 100, maximum: 132), spacing: 12)]
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(order) { item in
                        cell(item)
                            .opacity(dragID == item.id ? 0.25 : 1)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(
                                    targetID == item.id && dragID != item.id ? 0.9 : 0), lineWidth: 2.5))
                            .background(GeometryReader { g in
                                Color.clear.preference(key: RefFrameKey.self,
                                                       value: [item.id: g.frame(in: .named("reorder"))])
                            })
                            .gesture(drag(item))
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.never)

            // Floating copy of the dragged image, following the cursor.
            if let dragID, let f = frames[dragID], let item = order.first(where: { $0.id == dragID }) {
                cell(item, floating: true)
                    .frame(width: f.width, height: f.width)
                    .position(dragLocation)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(.named("reorder"))
        .onPreferenceChange(RefFrameKey.self) { frames = $0 }
        .onChange(of: items) { order = items }   // reflect external add/delete
    }

    private func cell(_ item: ReferenceStore.Item, floating: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06))
                .aspectRatio(1, contentMode: .fit)
                .overlay { ReorderThumb(item: item) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if !floating {
                Button { onDelete(item) } label: {
                    Image(systemName: "xmark.circle.fill").font(.body).foregroundStyle(.white, .black.opacity(0.5))
                }.buttonStyle(.plain).padding(4)
            }
        }
        .scaleEffect(floating ? 1.06 : 1)
        .shadow(color: .black.opacity(floating ? 0.3 : 0), radius: 12, y: 6)
    }

    private func drag(_ item: ReferenceStore.Item) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("reorder"))
            .onChanged { v in
                if dragID == nil { withAnimation(.easeOut(duration: 0.15)) { dragID = item.id } }
                dragLocation = v.location
            }
            .onEnded { v in
                defer { withAnimation(.easeOut(duration: 0.15)) { dragID = nil } }
                guard let from = order.firstIndex(where: { $0.id == item.id }),
                      let tID = nearestID(to: v.location),
                      let to = order.firstIndex(where: { $0.id == tID }), from != to else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
                onCommit(order.map(\.name))
            }
    }

    private func nearestID(to p: CGPoint) -> String? {
        frames.min(by: {
            hypot($0.value.midX - p.x, $0.value.midY - p.y) < hypot($1.value.midX - p.x, $1.value.midY - p.y)
        })?.key
    }
}

/// Reports each reorder cell's frame (static during a drag → no "multiple updates per frame").
private struct RefFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A cached thumbnail that fills its (square) cell.
private struct ReorderThumb: View {
    let item: ReferenceStore.Item
    @State private var image: Image?

    private var display: Image? {
        if let image { return image }
        if let cg = ThumbnailCache.shared.cached(item.url) { return Image(decorative: cg, scale: 1) }
        return nil
    }

    var body: some View {
        Group {
            if let display { display.resizable().scaledToFill() }
            else { Color.clear }
        }
        .task(id: item.url) {
            if ThumbnailCache.shared.cached(item.url) != nil { return }
            let box = await Task.detached(priority: .utility) { () -> SendableCGImage? in
                ReferenceStore.loadThumbnailCG(item.url, maxPixel: 300).map(SendableCGImage.init)
            }.value
            if let box { ThumbnailCache.shared.store(box.cg, item.url); image = Image(decorative: box.cg, scale: 1) }
        }
    }
}

/// The two add actions shown in a popover (a real Button renders custom styling; a Menu wouldn't).
private struct AddOptions: View {
    let onImport: () -> Void
    let onPaste: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            option("Import images…", "square.and.arrow.down", onImport)
            option("Paste from clipboard", "doc.on.clipboard", onPaste)
        }
        .padding(6).frame(width: 210)
    }
    private func option(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { dismiss(); action() } label: {
            Label(title, systemImage: icon).font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// The "Add" pill — accent tint + glare on hover.
private struct AddPill: View {
    let onImport: () -> Void
    let onPaste: () -> Void
    @State private var hover = false
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Label("Add", systemImage: "plus")
                .font(.callout.weight(.semibold)).foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.primary.opacity(hover ? 0.10 : 0.04)))
                .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(hover ? 0.20 : 0), .clear],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(hover ? 0.55 : 0.28)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .popover(isPresented: $show, arrowEdge: .bottom) { AddOptions(onImport: onImport, onPaste: onPaste) }
    }
}

/// The floating "+" — a bottom-centred circle that imports images. (Paste is via ⌘V; hint below.)
private struct AddFab: View {
    let onImport: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: onImport) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(hover ? 0.75 : 0.45), lineWidth: 1.5))
                .shadow(color: .white.opacity(hover ? 0.28 : 0.12), radius: hover ? 14 : 8)  // glow outside
                .scaleEffect(hover ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.18), value: hover)
    }
}

// MARK: - Helpers

private extension View {
    /// ⌘V paste of images/files — macOS only (iOS pastes go through the Add menu).
    @ViewBuilder func onImagePaste(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onPasteCommand(of: [.image, .fileURL]) { _ in action() }
        #else
        self
        #endif
    }
}

extension ReferenceBoardToolView {
    static let descriptor = ToolDescriptor(
        id: "reference-board", title: "Reference Board", defaultName: "Reference Board",
        summary: "A visual mood board — paste, import or drop images. Stored in your project folder.",
        icon: "photo.stack",
        // The storage folder is declared as the instance "file" (an extension-less token, so the
        // generic markdown machinery skips it) — this lets the board be DUPLICATED: a second instance
        // resolves to "Nidus References-2", etc. The canonical first instance keeps "Nidus References"
        // (nil files), so existing boards are untouched.
        validSizes: [.small, .wide, .medium, .large], files: [ReferenceStore.folderName],
        allowsMultiple: true,
        toolClass: .widget,
        makeView: { AnyView(ReferenceBoardToolView(context: $0)) }
    )
}
