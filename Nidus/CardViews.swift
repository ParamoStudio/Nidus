//
//  CardViews.swift
//  Nidus
//
//  Shared UI for the universal card: a compact row for a tool's tile (`CardRow`) and the expanded
//  detail popup (`CardDetailView`, shown over a blurred backdrop via WorkspaceOverlay). Tools reuse
//  these so every card looks and behaves consistently; each tool just decides what it surfaces.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A faint accent border a tool shows while a card is dragged over it.
struct CardDropHighlight: View {
    let active: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(active ? 0.7 : 0), lineWidth: 2)
            .animation(.easeOut(duration: 0.15), value: active)
            .allowsHitTesting(false)
    }
}

/// The card visual shared by the compact row and the drag "lifted" view. Note-based tools all render
/// this shape: title + a notes preview (always, even with images) and the cover thumbnail on the
/// right; a divider; then a compact footer of 🔗N · 🖼N · date. Kept short so cards stack densely.
private struct CardFace: View {
    let card: Card
    let folderURL: URL?

    private var thumbnail: Image? {
        guard let first = card.images.first,
              let url = folderURL?.appendingPathComponent(first) else { return nil }
        return nidusLoadImage(at: url)
    }

    // Flatten the note to symbol-free prose so a Markdown body (headings, tables, `**bold**`, links…)
    // reads calmly in the compact preview instead of showing its raw syntax.
    private var notesPreview: String {
        MarkdownParser.plainPreview(card.body)
    }
    private var hasLinks: Bool { !card.links.isEmpty }
    private var hasImages: Bool { !card.images.isEmpty }
    /// Numeric DD/MM/YYYY (locale-independent, very compact).
    private var dateText: String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: card.modified)
        return String(format: "%02d/%02d/%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !notesPreview.isEmpty {
                        Text(notesPreview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let thumbnail {
                    thumbnail.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.top, 12)  // leave the top-right corner free for the "…" menu
                }
            }
            Divider().opacity(0.5)
            footer
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 🔗N (only if references) · 🖼N (only if images), grouped left · date on the right.
    private var footer: some View {
        HStack(spacing: 12) {
            if hasLinks { footerItem("link", card.links.count) }
            if hasImages { footerItem("photo", card.images.count) }
            Spacer(minLength: 6)
            Text(dateText).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(height: 14)
    }

    private func footerItem(_ icon: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text("\(count)").font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

/// Compact card inside a tool tile. Press-and-drag moves it (custom drag, no system ghost);
/// double-click opens the detail popup. A min height keeps every card the same size.
struct CardRow: View {
    @Environment(NidusModel.self) private var model
    @Environment(CardDragController.self) private var drag

    let card: Card
    let folderURL: URL?
    /// The tool's `.md` and id, so dragging the card can move it to another tool.
    var sourceFile: URL? = nil
    var sourceTool: String = ""
    /// The tool's icon + name, so Space-to-open can label the popup the same as a click.
    var toolIcon: String = ""
    var toolName: String = ""
    /// Momentary accent ring when a search result reveals this card.
    var flashing: Bool = false
    let onOpen: () -> Void

    @State private var hovering = false

    private var isBeingDragged: Bool { drag.dragging?.card.id == card.id }

    var body: some View {
        CardFace(card: card, folderURL: folderURL)
            .overlay(alignment: .topTrailing) { ellipsisMenu }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(flashing ? 0.9 : 0), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .animation(.easeOut(duration: 0.25), value: flashing)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isBeingDragged ? 0.25 : 1) // the lifted card follows the cursor instead
            .onHover { inside in
                hovering = inside
                if inside {
                    drag.hovered = CardDragController.HoverInfo(
                        card: card, fileURL: sourceFile, folderURL: folderURL,
                        toolIcon: toolIcon, toolName: toolName)
                } else if drag.hovered?.card.id == card.id {
                    drag.hovered = nil
                }
            }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.easeOut(duration: 0.12), value: isBeingDragged)
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named("workspace"))
                    .onChanged { value in
                        guard let src = sourceFile else { return }
                        if drag.dragging == nil {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                drag.begin(card: card, sourceFile: src, sourceTool: sourceTool,
                                           folderURL: folderURL, at: value.location)
                            }
                        } else {
                            drag.move(to: value.location)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.18)) { drag.drop(model: model) }
                    }
            )
            // Single click opens (a drag needs ≥8pt, so a plain tap never starts a move) — matching
            // the newer tools (Event Log, Notebook, Reference Board) which all open on one click.
            .simultaneousGesture(TapGesture().onEnded { onOpen() })
    }

    /// The "…" menu (mockup top-right). Discreet — appears on hover.
    private var ellipsisMenu: some View {
        Menu {
            Button { onOpen() } label: { Label("Open", systemImage: "arrow.up.left.and.arrow.down.right") }
            Button(role: .destructive) { deleteSelf() } label: { Label("Delete card", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.regularMaterial).opacity(hovering ? 1 : 0))
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(hovering ? 1 : 0)
        .padding(8)
    }

    private func deleteSelf() {
        guard let src = sourceFile else { return }
        if let folder = folderURL {
            for rel in card.images { model.deleteCardImage(rel, inProjectFolder: folder) }
        }
        CardStore.remove(id: card.id, from: src)
        model.notifyFileChange()
    }
}

/// Wraps a tool's card list: when a search result targets THIS instance (matching slotID + ref), it
/// scrolls to that card and flashes it (rows read the `flashID` binding). Reused by every card tool.
struct RevealingList<Content: View>: View {
    @Environment(NidusModel.self) private var model
    let slotID: String
    let ref: ProjectRef
    @Binding var flashID: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            TidyScroll { content() }
                .onChange(of: model.revealTarget) { _, t in reveal(t, proxy) }
                .onAppear {
                    // Fresh window (a cross-project jump): let layout settle, then reveal.
                    let t = model.revealTarget
                    Task { @MainActor in try? await Task.sleep(for: .seconds(0.12)); reveal(t, proxy) }
                }
        }
    }

    private func reveal(_ target: RevealTarget?, _ proxy: ScrollViewProxy) {
        guard let t = target, t.ref == ref, t.slotID == slotID else { return }
        model.revealTarget = nil  // consume it so later appearances don't re-flash
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(t.cardID, anchor: .center) }
        flashID = t.cardID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if flashID == t.cardID { flashID = nil }
        }
    }
}

/// The real card "lifted" under the cursor while dragging — crisp and elevated, no translucent ghost.
struct CardFloatingView: View {
    let card: Card
    let folderURL: URL?
    var body: some View {
        CardFace(card: card, folderURL: folderURL)
            .frame(width: 260)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.30), radius: 16, y: 6)
            .scaleEffect(1.03)
    }
}

/// The expanded card — a reusable viewer + editor, shared by additive tools. Layout follows the
/// canonical mockup: a header (tool icon + name on the left, close on the right); a large CONTAINED
/// image viewer on the left with a fit/fill control bottom-left; and an info column on the right —
/// title with an Edit toggle, Notes, References, then the Images strip at the bottom and a discreet
/// "Delete card". The default state is a clean reader; Edit makes the title + notes editable.
/// References and images are managed inline; Delete also clears the card's `_assets/` files.
struct CardDetailView: View {
    @Environment(NidusModel.self) private var model
    @Environment(\.openURL) private var openURL
    let card: Card
    let fileURL: URL?
    let folderURL: URL?
    /// The owning tool's icon + display name, shown in the header so the popup feels "inside" it.
    var toolIcon: String = ""
    var toolName: String = ""
    let onClose: () -> Void

    private enum Mode { case view, edit }

    @State private var title: String
    @State private var bodyText: String
    @State private var images: [String]
    @State private var links: [CardLink]
    @State private var selected: Int = 0      // the COVER (chosen in edit mode); saved as images[0]
    @State private var previewIndex: Int = 0  // which image the viewer shows right now (navigable)
    @State private var newLinkName: String = ""
    @State private var newLinkURL: String = ""
    // One file importer serves both the card's images and the micro-tool `.js` import — SwiftUI only
    // honours a single `.fileImporter` per view, so two separate ones silently break each other.
    private enum ImportKind { case image, tool }
    @State private var importKind: ImportKind?
    @State private var imageFill = false      // off (default) = whole image; on = fill/crop the frame
    @State private var notesWidth: CGFloat = 0  // measured editor width → drives the notes box height
    @State private var bodySelection: TextSelection?  // caret/selection in the notes editor (toolbar targets this)
    @State private var mode: Mode = .view      // .edit only reveals delete / cover-select controls
    @State private var deleted = false         // set on delete so the save-on-close doesn't resurrect it
    @State private var viewerHover = false
    @State private var microTools: [MicroTool] = []   // vault-wide, loaded on appear
    @State private var runningTool: MicroTool?         // the micro-tool popup currently open
    @State private var showMicroManager = false        // the manage/import panel currently open
    @State private var microToolImportError: String?   // shown inline in the manager on a failed import
    @FocusState private var rootFocused: Bool

    init(card: Card, fileURL: URL?, folderURL: URL?,
         toolIcon: String = "", toolName: String = "", onClose: @escaping () -> Void) {
        self.card = card
        self.fileURL = fileURL
        self.folderURL = folderURL
        self.toolIcon = toolIcon
        self.toolName = toolName
        self.onClose = onClose
        _title = State(initialValue: card.title)
        _bodyText = State(initialValue: card.body)
        _images = State(initialValue: card.images)
        _links = State(initialValue: card.links)
    }

    private func imageURL(_ rel: String) -> URL? { folderURL?.appendingPathComponent(rel) }
    private var hasImages: Bool { !images.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 24) {
                if hasImages { viewer.frame(width: 380) }
                info.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
            .frame(maxHeight: .infinity)
        }
        // Fixed panel — the info column scrolls if it overflows; the notes box grows up to 8 lines.
        .frame(width: hasImages ? 920 : 540, height: 540)
        .glassCard()
        .contentShape(Rectangle())
        // Swallow taps on empty chrome so they don't fall through to the dismiss backdrop.
        // simultaneousGesture so it coexists with the title/notes text fields (doesn't steal focus).
        .simultaneousGesture(TapGesture().onEnded {})
        // Escape closes from anywhere (a command, so it fires even while a field is focused).
        .background(Button("", action: close).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
        // The card holds key focus by default, so ←/→ browse photos whenever no text field is active.
        // A focused TextField consumes the arrows itself (cursor moves), so navigation pauses while typing.
        .focusable(hasImages)
        .focusEffectDisabled()
        .focused($rootFocused)
        .onAppear { rootFocused = true }
        .onKeyPress(.leftArrow) { images.count > 1 ? { step(-1); return .handled }() : .ignored }
        .onKeyPress(.rightArrow) { images.count > 1 ? { step(1); return .handled }() : .ignored }
        // Closing — via the X, Escape, or tapping outside the card — all persist the same way.
        .onDisappear { if !deleted { save() } }
        // Micro-tools: a floating column just OUTSIDE the card's right edge (collapsed hint → expands
        // upward in Edit mode). Output is copied to the clipboard; you paste it into the note.
        .overlay(alignment: .bottomTrailing) {
            if runningTool == nil {
                MicroToolBar(tools: microTools, expanded: mode == .edit,
                             onRun: { runningTool = $0 },
                             onManage: { showMicroManager = true },
                             onDelete: deleteMicroTool)
                    .offset(x: 68, y: -14)   // sit outside the panel, same bottom zone as before
            }
        }
        .overlay { microToolRunner }
        .overlay { microToolManagerOverlay }
        .onAppear { microTools = MicroToolStore.installed(vaultURL: model.vaultURL) }
        // Images go through SwiftUI's `.fileImporter` (only kind left on it — see `installMicroTool`
        // for why the micro-tool `.js` import bypasses this entirely on macOS).
        .fileImporter(isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
                      allowedContentTypes: importKind == .tool ? [.javaScript] : [.image],
                      allowsMultipleSelection: true) { result in
            let kind = importKind
            importKind = nil
            guard case .success(let urls) = result else {
                if case .failure(let err) = result {
                    print("[MicroTools] file picker returned failure: \(err)")
                }
                return
            }
            switch kind {
            case .image: addImages(urls)
            case .tool: if let url = urls.first { installMicroTool(url) }
            case .none: break
            }
        }
    }

    /// Copies + parses a `.js` into the vault's `_microtools/`, refreshing the list on success or
    /// surfacing an inline error on failure.
    private func installMicroTool(_ url: URL) {
        print("[MicroTools] importing \(url.path), vaultURL=\(model.vaultURL?.path ?? "nil")")
        if let tool = MicroToolStore.install(from: url, vaultURL: model.vaultURL) {
            print("[MicroTools] installed '\(tool.name)' (id=\(tool.id)) at \(tool.sourceURL.path)")
            microTools = MicroToolStore.installed(vaultURL: model.vaultURL)
            microToolImportError = nil
        } else {
            print("[MicroTools] install FAILED for \(url.path)")
            microToolImportError = "Couldn't import \(url.lastPathComponent) — it doesn't parse as a valid micro-tool."
            showMicroManager = true   // reopen so the error is actually visible
        }
    }

    #if os(macOS)
    /// Micro-tool import on macOS uses `NSOpenPanel` directly instead of SwiftUI's `.fileImporter` —
    /// on this view its completion handler was never firing for a `.tool` import (root cause unclear;
    /// possibly this view's re-presentation via `WorkspaceOverlay`'s `AnyView` confuses `.fileImporter`'s
    /// internal state). `NSOpenPanel` sidesteps that SwiftUI machinery entirely.
    private func presentMicroToolImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.javaScript]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            installMicroTool(url)
        }
    }
    #endif

    /// Imports image FILES (from the picker or a drag & drop) into the card's `_assets/`.
    private func addImages(_ urls: [URL]) {
        guard let folderURL else { return }
        for url in urls {
            if let rel = model.importCardImage(from: url, intoProjectFolder: folderURL) { images.append(rel) }
        }
        if !images.isEmpty { previewIndex = images.count - 1 }
        save()
    }

    /// Adds whatever image is on the clipboard (a pasted screenshot's data, or copied image files).
    private func pasteImages() {
        guard let folderURL else { return }
        let urls = ReferenceStore.clipboardImageURLs()
        if !urls.isEmpty {
            addImages(urls)
        } else if let png = ReferenceStore.clipboardImagePNG(),
                  let rel = model.saveCardImage(png, ext: "png", intoProjectFolder: folderURL) {
            images.append(rel)
            previewIndex = images.count - 1
            save()
        }
    }

    private func deleteMicroTool(_ tool: MicroTool) {
        MicroToolStore.uninstall(tool)
        microTools = MicroToolStore.installed(vaultURL: model.vaultURL)
    }

    /// The micro-tool popup — a proper modal dimming the whole screen (the runner is wider than the
    /// card, so it must float free, not clipped to the panel). Tap outside or Esc closes it (nothing
    /// to save — the tool only ever copies to the clipboard).
    @ViewBuilder private var microToolRunner: some View {
        if let tool = runningTool {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .frame(width: 5000, height: 5000)   // cover the whole window, beyond the card
                    .onTapGesture { runningTool = nil }
                MicroToolRunnerView(tool: tool) { runningTool = nil }
            }
            .transition(.opacity)
        }
    }

    /// Install/uninstall micro-tools — a plain overlay (not `.popover`), so on macOS the Import button
    /// can hand off straight to `NSOpenPanel` (see `presentMicroToolImportPanel`).
    @ViewBuilder private var microToolManagerOverlay: some View {
        if showMicroManager {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .frame(width: 5000, height: 5000)   // cover the whole window, beyond the card
                    .onTapGesture { showMicroManager = false }
                MicroToolManager(tools: microTools,
                                 errorMessage: microToolImportError,
                                 onImport: {
                                     microToolImportError = nil
                                     showMicroManager = false
                                     #if os(macOS)
                                     presentMicroToolImportPanel()
                                     #else
                                     importKind = .tool
                                     #endif
                                 },
                                 onDelete: deleteMicroTool)
            }
            .transition(.opacity)
        }
    }

    // MARK: Header (tool identity + close)

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: toolIcon.isEmpty ? "rectangle.on.rectangle" : toolIcon)
                .font(.title3).foregroundStyle(.secondary)
            Text(toolName.isEmpty ? "Card" : toolName)
                .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            HoverCircleButton(systemName: "xmark", action: close)
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 10)
    }

    // MARK: Left viewer (contained — the image never escapes the box)

    private var viewer: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay {
                if images.indices.contains(previewIndex), let url = imageURL(images[previewIndex]),
                   let img = nidusLoadImage(at: url) {
                    img.resizable().aspectRatio(contentMode: imageFill ? .fill : .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .leading) { if images.count > 1 { navChevron("chevron.left") { step(-1) } } }
            .overlay(alignment: .trailing) { if images.count > 1 { navChevron("chevron.right") { step(1) } } }
            .overlay(alignment: .bottomLeading) { fitFillToggle }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onHover { viewerHover = $0 }
            .onTapGesture { rootFocused = true }  // clicking the image returns key focus to the card
    }

    /// A side navigation chevron over the viewer (shown on hover when there's more than one image).
    private func navChevron(_ system: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .padding(10)
        .opacity(viewerHover ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: viewerHover)
    }

    private func step(_ delta: Int) {
        guard !images.isEmpty else { return }
        previewIndex = (previewIndex + delta + images.count) % images.count
    }

    private var fitFillToggle: some View {
        Button { imageFill.toggle() } label: {
            Image(systemName: imageFill ? "arrow.down.right.and.arrow.up.left"
                                        : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .padding(14)
        .help(imageFill ? "Fit the whole image" : "Fill the frame")
    }

    // MARK: Right info column

    private var info: some View {
        // The title + Edit control stay PINNED at the top; everything below scrolls under them, so
        // you never lose "which card is this / how do I edit it" when reading a long note.
        VStack(alignment: .leading, spacing: 14) {
            titleRow
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    notesSection
                    // "Assets and tools" (links) stays out of the way in view mode — shown only while
                    // editing, or if the card already has some (so existing links are never hidden).
                    // References (images) always show — they're the visual identity of the card.
                    if mode == .edit || !links.isEmpty {
                        section("Assets and tools") { referencesView }
                    }
                    section("References") { imagesView }
                    HStack { Spacer(); deleteButton }
                }
                // Extra bottom room so the delete pill can scroll clear of the floating micro-tool
                // bar in the corner (it never sits under it).
                .padding(.bottom, 54)
            }
            .scrollIndicators(.never)   // no visible scrollbar for the info column (still scrollable)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // Always editable — clicking the title (or notes) edits in place; no mode needed.
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold))
            Spacer(minLength: 8)
            // Edit only toggles the delete / cover-select controls on attachments + notes.
            HoverPill(title: mode == .view ? "Edit" : "Done",
                      systemImage: mode == .view ? "pencil" : "checkmark") { toggleMode() }
        }
    }

    private func section<C: View>(_ heading: String, @ViewBuilder _ inner: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(.caption.weight(.semibold)).textCase(.uppercase)
                .tracking(1).foregroundStyle(.secondary)
            inner()
        }
    }

    // MARK: Notes (always editable in place; grows with content, caps at 8 lines then scrolls)

    private let notesLine: CGFloat = 21
    private let notesVInset: CGFloat = 16   // editor's vertical padding (8 top + 8 bottom)
    private let notesHInset: CGFloat = 28   // horizontal padding + TextEditor's own text insets
    private var notesMinHeight: CGFloat { notesLine + notesVInset }
    private var notesMaxHeight: CGFloat { notesLine * 8 + notesVInset }

    /// Height the notes box should take: the text's natural height at the current width, clamped to
    /// 1…8 lines. Measured with font metrics (NOT a constrained mirror view — that always returned
    /// the min, which is why it never grew before).
    private var notesContentHeight: CGFloat {
        let inner = max(1, notesWidth - notesHInset)
        let h = measuredTextHeight(bodyText.isEmpty ? " " : bodyText, width: inner) + notesVInset
        return min(max(h, notesMinHeight), notesMaxHeight)
    }

    private func measuredTextHeight(_ s: String, width: CGFloat) -> CGFloat {
        #if canImport(AppKit)
        let font = NSFont.preferredFont(forTextStyle: .callout)
        #else
        let font = UIFont.preferredFont(forTextStyle: .callout)
        #endif
        let para = NSMutableParagraphStyle(); para.lineSpacing = 3
        let rect = (s as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: para], context: nil)
        return ceil(rect.height)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notes").font(.caption.weight(.semibold)).textCase(.uppercase)
                    .tracking(1).foregroundStyle(.secondary)
                Spacer()
                if mode == .edit && !bodyText.isEmpty {
                    Button { withAnimation(.easeOut(duration: 0.12)) { bodyText = "" } } label: {
                        Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("Clear the whole note")
                }
            }
            if mode == .edit { mdToolbar }
            if mode == .edit { notesEditor } else { notesRendered }
        }
    }

    // A small, subtle row of the most basic Markdown actions — not every syntax there is, just the
    // handful that make a card's notes worth writing structured content into (incl. pasted tables
    // from future micro-tools, e.g. a glaze/recipe normalizer).
    private var mdToolbar: some View {
        HStack(spacing: 4) {
            MDToolButton(systemName: "bold", help: "Bold") { wrapSelection("**") }
            MDToolButton(systemName: "italic", help: "Italic") { wrapSelection("*") }
            Divider().frame(height: 14).opacity(0.4)
            MDToolButton(systemName: "textformat.size", help: "Heading") { applyLinePrefix("## ") }
            MDToolButton(systemName: "list.bullet", help: "Bullet list") { applyLinePrefix("- ") }
            MDToolButton(systemName: "list.number", help: "Numbered list") { applyLinePrefix("1. ") }
            Divider().frame(height: 14).opacity(0.4)
            MDToolButton(systemName: "tablecells", help: "Table") { insertTable() }
            Spacer(minLength: 0)
        }
    }

    private var notesEditor: some View {
        TextEditor(text: $bodyText, selection: $bodySelection)
            .font(.callout).lineSpacing(3).scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(height: notesContentHeight)
            .background(panelBackground)
            // Probe only the width (height comes from the text metrics above, so no feedback loop).
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { notesWidth = g.size.width }
                    .onChange(of: g.size.width) { notesWidth = g.size.width }
            })
    }

    /// View mode: the notes rendered as actual Markdown (headings/lists/tables), read-only. No inner
    /// scroll — it's embedded straight into the info column's flow, which already scrolls as a whole
    /// (a boxed inner scroll would mean scrolling twice). A faint border — just a couple of shades
    /// lighter than the panel — outlines the notes zone so it reads as one region at a glance.
    private var notesRendered: some View {
        markdownContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder private var markdownContent: some View {
        let blocks = MarkdownParser.parse(bodyText)
        if blocks.isEmpty {
            Text("No notes").font(.callout).foregroundStyle(.tertiary)
        } else {
            MarkdownView(blocks: blocks)
        }
    }

    // MARK: Markdown toolbar actions — operate on the caret/selection inside the notes editor.

    private func selectedRange() -> Range<String.Index> {
        switch bodySelection?.indices {
        case .selection(let r): return r
        case .multiSelection(let set): return set.ranges.first ?? bodyText.endIndex..<bodyText.endIndex
        case .none: return bodyText.endIndex..<bodyText.endIndex
        }
    }

    /// Bold/Italic: wraps the selection in `marker`, or inserts an empty pair with the caret in
    /// between when nothing is selected.
    private func wrapSelection(_ marker: String) {
        let r = selectedRange()
        if r.isEmpty {
            bodyText.insert(contentsOf: marker + marker, at: r.lowerBound)
            let mid = bodyText.index(r.lowerBound, offsetBy: marker.count)
            bodySelection = TextSelection(insertionPoint: mid)
        } else {
            let start = r.lowerBound
            let replacement = marker + bodyText[r] + marker
            bodyText.replaceSubrange(r, with: replacement)
            let end = bodyText.index(start, offsetBy: replacement.count)
            bodySelection = TextSelection(range: start..<end)
        }
    }

    /// Heading/bullet/numbered list: prefixes the line the caret is on.
    private func applyLinePrefix(_ prefix: String) {
        let caret = selectedRange().lowerBound
        let lineStart = bodyText.lineRange(for: caret..<caret).lowerBound
        bodyText.insert(contentsOf: prefix, at: lineStart)
        bodySelection = TextSelection(insertionPoint: bodyText.index(lineStart, offsetBy: prefix.count))
    }

    /// Inserts a ready-to-fill 2×2 table template at the caret (own paragraph, blank lines around it).
    private func insertTable() {
        let caret = selectedRange().lowerBound
        let needsLeadingBreak = caret != bodyText.startIndex && bodyText[bodyText.index(before: caret)] != "\n"
        let template = (needsLeadingBreak ? "\n\n" : "") + "| Header | Header |\n| --- | --- |\n| Cell | Cell |\n"
        bodyText.insert(contentsOf: template, at: caret)
        bodySelection = TextSelection(insertionPoint: bodyText.index(caret, offsetBy: template.count))
    }

    /// A small, subtle icon button for the Markdown toolbar (no persistent chrome, just a hover tint).
    private struct MDToolButton: View {
        let systemName: String
        var help: String = ""
        let action: () -> Void
        @State private var hover = false
        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 26, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hover ? 0.10 : 0)))
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
            .help(help)
        }
    }

    // MARK: Assets and tools (named links, opened externally)

    private var referencesView: some View {
        VStack(spacing: 0) {
            ForEach(Array(links.enumerated()), id: \.element.id) { idx, _ in
                if idx != 0 { Divider().opacity(0.5) }
                refRow(at: idx)
            }
            if !links.isEmpty { Divider().opacity(0.5) }
            addRefRow
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func refRow(at idx: Int) -> some View {
        let link = links[idx]
        return HStack(spacing: 11) {
            Image(systemName: "link").font(.callout).foregroundStyle(.secondary)
            if mode == .edit {
                // Edit reveals both fields (name + link) and a delete.
                TextField("Name", text: $links[idx].title)
                    .textFieldStyle(.plain).font(.callout)
                    .frame(maxWidth: 130, alignment: .leading)
                Divider().frame(height: 16).opacity(0.5)
                TextField("Link", text: $links[idx].url)
                    .textFieldStyle(.plain).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            } else {
                // Once fixed, only the name shows.
                Text(link.title.isEmpty ? link.url : link.title)
                    .font(.callout).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if mode == .edit {
                Button { links.remove(at: idx) } label: {
                    Image(systemName: "xmark.circle.fill").font(.callout).foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
            Button { open(link.url) } label: {
                Image(systemName: "arrow.up.right").font(.callout).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { if mode == .view { open(link.url) } }
    }

    private var addRefRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").font(.callout).foregroundStyle(.secondary)
            TextField("Name", text: $newLinkName)
                .textFieldStyle(.plain).font(.callout)
                .frame(maxWidth: 130, alignment: .leading)
                .onSubmit(addLink)
            Divider().frame(height: 16).opacity(0.5)
            TextField("Link", text: $newLinkURL)
                .textFieldStyle(.plain).font(.callout)
                .onSubmit(addLink)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: Images (thumbnails — the open one is the cover; "+" imports)

    private var imagesView: some View {
        HStack(spacing: 12) {
            ForEach(Array(images.enumerated()), id: \.offset) { idx, rel in
                thumb(idx: idx, rel: rel)
            }
            // The "+" opens the picker, but also accepts a dragged image and a paste while hovered.
            GlareAddButton(action: { importKind = .image },
                           onDrop: { addImages($0) },
                           onPaste: { pasteImages() })
        }
    }

    private func thumb(idx: Int, rel: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let url = imageURL(rel), let img = nidusLoadImage(at: url) {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else { Color.primary.opacity(0.06) }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // Accent ring = the cover; a faint ring = the image currently shown in the viewer.
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    selected == idx ? Color.accentColor
                        : (previewIndex == idx ? Color.primary.opacity(0.3) : Color.clear),
                    lineWidth: selected == idx ? 2.5 : (previewIndex == idx ? 1.5 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { previewIndex = idx; rootFocused = true }  // browse it (any mode); keep key focus
            if mode == .edit {
                HStack(spacing: 4) {
                    Button { selected = idx; previewIndex = idx } label: {
                        Image(systemName: selected == idx ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle(selected == idx ? Color.accentColor : Color.white)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                    }.buttonStyle(.plain).help("Use as cover")
                    Button { removeImage(idx) } label: {
                        Image(systemName: "xmark.circle.fill").font(.body)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }.buttonStyle(.plain)
                }
                .padding(5)
            }
        }
    }

    /// The dashed "add image" tile — click to pick, DROP an image on it, or hover + ⌘V to paste one.
    /// Glare + lift on hover; a stronger ring while a drag is over it.
    private struct GlareAddButton: View {
        let action: () -> Void
        var onDrop: ([URL]) -> Void = { _ in }
        var onPaste: () -> Void = {}
        @State private var hover = false
        @State private var targeted = false
        @FocusState private var focused: Bool
        private var active: Bool { hover || targeted }
        var body: some View {
            Button(action: action) {
                Image(systemName: "plus").font(.title3).foregroundStyle(.secondary)
                    .scaleEffect(active ? 1.18 : 1)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(active ? 0.06 : 0)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(active ? 0.28 : 0), .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(active ? 0.35 : 0.2),
                                      style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [5, 5])))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable().focusEffectDisabled().focused($focused)
            // Focus while hovered so a ⌘V paste lands on this control.
            .onHover { hover = $0; focused = $0 }
            .dropDestination(for: URL.self) { urls, _ in onDrop(urls); return true } isTargeted: { targeted = $0 }
            .onImagePasteHere { onPaste() }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
        }
    }

    private var deleteButton: some View {
        // Soft and integrated — same pill language as Edit, not an alarming red.
        HoverPill(title: "Delete card", systemImage: "trash") { deleteCard() }
    }

    /// The soft rounded panel used by Notes and References.
    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
    }

    // MARK: Actions

    private func toggleMode() {
        withAnimation(.easeOut(duration: 0.15)) { mode = (mode == .view ? .edit : .view) }
    }

    private func open(_ urlString: String) {
        if let u = urlString.asOpenableURL { openURL(u) }
    }

    private func addLink() {
        let url = newLinkURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        let name = newLinkName.trimmingCharacters(in: .whitespaces)
        links.append(CardLink(title: name.isEmpty ? linkDisplayTitle(for: url) : name, url: url))
        newLinkName = ""; newLinkURL = ""
    }

    private func removeImage(_ idx: Int) {
        guard images.indices.contains(idx) else { return }
        let rel = images.remove(at: idx)
        if let folderURL { model.deleteCardImage(rel, inProjectFolder: folderURL) } // gone from disk for good
        if selected >= images.count { selected = max(0, images.count - 1) }
        if previewIndex >= images.count { previewIndex = max(0, images.count - 1) }
        save()  // persist the removal right away
    }

    private func save() {
        guard let fileURL else { return }
        // The image left open in the viewer becomes the cover (first).
        var ordered = images
        if ordered.indices.contains(selected), selected != 0 {
            ordered.insert(ordered.remove(at: selected), at: 0)
        }
        var updated = card
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? card.title : trimmed
        updated.body = bodyText
        updated.images = ordered
        updated.links = links
        CardStore.update(updated, in: fileURL)
        model.notifyFileChange()
    }

    private func close() { save(); onClose() }

    private func deleteCard() {
        deleted = true  // so .onDisappear's save-on-close won't rewrite the card we just removed
        // Clear the card's image files so deleting it doesn't leave `_assets/` noise behind.
        if let folderURL {
            for rel in images { model.deleteCardImage(rel, inProjectFolder: folderURL) }
        }
        if let fileURL {
            CardStore.remove(id: card.id, from: fileURL)
            model.notifyFileChange()
        }
        onClose()
    }

    /// A small, hover-reactive circular icon button (the header close control).
    private struct HoverCircleButton: View {
        let systemName: String
        let action: () -> Void
        @State private var h = false
        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(h ? 0.14 : 0.07)))
            }
            .buttonStyle(.plain)
            .onHover { h = $0 }
            .animation(.easeOut(duration: 0.12), value: h)
        }
    }

    /// An outlined, hover-reactive pill button (Edit / Done, Delete card).
    private struct HoverPill: View {
        let title: String
        let systemImage: String
        var tint: Color = .primary
        let action: () -> Void
        @State private var h = false
        var body: some View {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(tint.opacity(h ? 0.10 : 0)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(h ? 0.22 : 0.14)))
            }
            .buttonStyle(.plain)
            .onHover { h = $0 }
            .animation(.easeOut(duration: 0.12), value: h)
        }
    }
}

extension View {
    /// Fires `action` on a ⌘V paste of an image or image file (macOS). No-op on iOS.
    @ViewBuilder func onImagePasteHere(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onPasteCommand(of: [.image, .fileURL]) { _ in action() }
        #else
        self
        #endif
    }
}
