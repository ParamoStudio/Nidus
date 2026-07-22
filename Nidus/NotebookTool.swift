//
//  NotebookTool.swift
//  Nidus
//
//  Notebook — a lightweight notes-and-documents library scoped to the project. Notes are our own
//  Markdown files (edited in-app); documents (pdf/txt/docx/odt/pages/rtf) are imported and previewed
//  via QuickLook / opened in their own app. Everything lives in one real `Notebook` folder inside the
//  project's vault folder. Groups are real subfolders, shown as Apple Books-style shelf rows; up to
//  two items per row can be anchored (pinned) to the front. Single instance per project by design —
//  this tool is deliberately not duplicable.
//
//  The tile is a compact recent-items card; the tool opens into a full library (browse, search,
//  group via Select mode, add via the classic "+" tile). Notes open in the editor; documents in the
//  QuickLook viewer.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Tile (closed view)

struct NotebookToolView: View {
    @Environment(NidusModel.self) private var model
    @Environment(WorkspaceOverlay.self) private var overlay
    let context: ToolContext

    private var projectFolder: URL? { context.folderURL }
    private var recent: [NotebookStore.Item] {
        _ = model.fileChangeTick
        return NotebookStore.load(projectFolder: projectFolder)
            .flatMap(\.items)
            .sorted { $0.modified > $1.modified }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recent.isEmpty {
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Image(systemName: "book.closed").font(.title2).foregroundStyle(.tertiary)
                    Text("No notes or documents yet.").font(.caption).foregroundStyle(.tertiary)
                    Button { open() } label: {
                        Label("Add or write", systemImage: "plus")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { open() }
            } else {
                TidyScroll {
                    VStack(alignment: .leading, spacing: 2) {
                        // A recent item opens straight to itself (its editor / viewer).
                        ForEach(recent.prefix(6)) { item in
                            NotebookRow(item: item) { open(item) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // The footer opens the whole library (the browse view).
                Button { open() } label: {
                    HStack(spacing: 4) {
                        Text("Open Notebook").font(.caption.weight(.medium))
                        Image(systemName: "arrow.right").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Opens the full library (browse view). A tile's header area / "Open Notebook" uses this.
    private func open() { present(item: nil) }
    /// Opens the library straight to a specific item.
    private func open(_ item: NotebookStore.Item) { present(item: item) }

    private func present(item: NotebookStore.Item?) {
        let folder = projectFolder, name = context.name
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                NotebookLibraryView(projectFolder: folder, toolName: name, initialItem: item) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }
}

extension NotebookToolView {
    static let descriptor = ToolDescriptor(
        id: "notebook", title: "Notebook", defaultName: "Notebook",
        summary: "A lightweight library of notes and documents for the project — write Markdown, import PDFs and files.",
        icon: "book.pages",
        validSizes: [.small, .medium], files: [],
        allowsMultiple: false,
        toolClass: .widget,   // its own file library, not a card drop-sink
        // The hotkey opens the library straight into a fresh note (special-cased in WorkspaceView —
        // the `kind` is unused for Notebook, which doesn't do line-append quick capture).
        quickAction: ToolQuickAction(defaultHotkey: "n", label: "New Note", kind: .idea),
        makeView: { AnyView(NotebookToolView(context: $0)) }
    )
}

/// One compact line in the tile: type icon + title + subtitle. Hover-reactive; click opens the item.
private struct NotebookRow: View {
    let item: NotebookStore.Item
    let onOpen: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: NotebookIcon.symbol(for: item))
                .font(.callout).foregroundStyle(NotebookIcon.tint(for: item))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                Text(NotebookIcon.subtitle(for: item)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if hover { Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(hover ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { onOpen() }
    }
}

// MARK: - Type icon / labels

enum NotebookIcon {
    static func symbol(for item: NotebookStore.Item) -> String {
        if item.isNote { return "doc.text" }
        switch item.ext {
        case "pdf":            return "doc.richtext"
        case "txt":            return "doc.plaintext"
        case "docx", "odt", "pages", "rtf": return "doc"
        default:               return "doc"
        }
    }
    static func tint(for item: NotebookStore.Item) -> Color {
        if item.isNote { return .accentColor }
        switch item.ext {
        case "pdf":  return Color(hex: "D0574B")
        case "txt":  return Color(hex: "8B909A")
        default:     return Color(hex: "5B7FE0")
        }
    }
    static func typeLabel(for item: NotebookStore.Item) -> String {
        if item.isNote { return "Markdown note" }
        return item.ext.uppercased()
    }
    static func subtitle(for item: NotebookStore.Item) -> String {
        typeLabel(for: item) + " · " + relativeEdited(item.modified)
    }
    static func relativeEdited(_ date: Date) -> String {
        if date == .distantPast { return "—" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        // "Edited yesterday" reads better than the abbreviated form for very recent items.
        if Calendar.current.isDateInToday(date) { return "today" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        return f.localizedString(for: date, relativeTo: Date())
    }
}
