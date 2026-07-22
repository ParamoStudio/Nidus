//
//  NotebookTiles.swift
//  Nidus
//
//  The big shelf tiles for the Notebook library: an item tile (type icon, title, subtitle, anchor
//  pin, select checkmark) and the classic dashed "+" add tile (click → import/create menu,
//  double-click → new note, hover + ⌘V → paste a file or text).
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Item tile

struct NotebookTileView: View {
    let item: NotebookStore.Item
    let anchored: Bool
    let selectMode: Bool
    let selected: Bool
    let onOpen: () -> Void
    let onToggleSelect: () -> Void
    let onToggleAnchor: () -> Void

    @State private var hover = false

    private var tint: Color { NotebookIcon.tint(for: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.callout.weight(.medium))
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text(NotebookIcon.subtitle(for: item)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
        .frame(width: 150)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { selectMode ? onToggleSelect() : onOpen() }
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12))
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.18))
            Image(systemName: NotebookIcon.symbol(for: item))
                .font(.system(size: 34, weight: .regular)).foregroundStyle(tint)
        }
        .frame(width: 150, height: 104)
        .overlay(alignment: .topTrailing) { corner }
        .overlay(alignment: .bottomTrailing) {
            Text(item.isNote ? "MD" : item.ext.uppercased())
                .font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .padding(6)
        }
        .scaleEffect(hover && !selectMode ? 1.02 : 1)
        .animation(.easeOut(duration: 0.14), value: hover)
    }

    @ViewBuilder private var corner: some View {
        if selectMode {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(selected ? Color.accentColor : .secondary)
                .background(Circle().fill(.background).opacity(selected ? 1 : 0.001))
                .padding(6)
        } else if anchored || hover {
            Button(action: onToggleAnchor) {
                Image(systemName: anchored ? "pin.fill" : "pin")
                    .font(.caption).foregroundStyle(anchored ? Color.accentColor : .secondary)
                    .padding(5).background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .help(anchored ? "Unpin from the front of this row" : "Pin to the front of this row")
            .padding(6)
        }
    }
}

// MARK: - Add tile (import / create / paste)

struct NotebookAddTile: View {
    let onImport: () -> Void
    let onNewNote: () -> Void
    let onPaste: () -> Void
    var onDropFiles: ([URL]) -> Void = { _ in }

    @State private var hover = false
    @State private var targeted = false
    @State private var showMenu = false
    @State private var lastTapTime: Date?
    @State private var clickToken = 0
    @FocusState private var focused: Bool

    private var active: Bool { hover || targeted }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            tile
            Text("Add").font(.caption2).foregroundStyle(.tertiary).frame(width: 150, alignment: .leading)
        }
        .frame(width: 150)
    }

    private var tile: some View {
        Button(action: handleTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(active ? 0.05 : 0))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(active ? 0.35 : 0.2),
                                  style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [5, 5]))
                Image(systemName: "plus").font(.title2).foregroundStyle(.secondary)
                    .scaleEffect(active ? 1.15 : 1)
            }
            .frame(width: 150, height: 104)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable().focusEffectDisabled().focused($focused)
        .onHover { hover = $0; focused = $0 }
        .dropDestination(for: URL.self) { urls, _ in handleDrop(urls); return true } isTargeted: { targeted = $0 }
        .pasteTrigger { onPaste() }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) { menu }
        .help("Click to import or create · double-click for a new note · hover + ⌘V to paste")
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { showMenu = false; onNewNote() } label: {
                Label("Create note", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { showMenu = false; onImport() } label: {
                Label("Import file…", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: 190)
    }

    // Single click → import/create menu (after a short beat, so a double-click can pre-empt it).
    // Double click → straight to a new note. Never paste on a click — only hover + ⌘V does that.
    private func handleTap() {
        let now = Date()
        if let last = lastTapTime, now.timeIntervalSince(last) < 0.32 {
            lastTapTime = nil
            clickToken &+= 1               // cancel the pending single-click menu
            onNewNote()
        } else {
            lastTapTime = now
            let token = clickToken &+ 1
            clickToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) {
                if clickToken == token { showMenu = true }
            }
        }
    }

    private func handleDrop(_ urls: [URL]) {
        let importable = urls.filter { NotebookStore.importableExtensions.contains($0.pathExtension.lowercased()) }
        if !importable.isEmpty { onDropFiles(importable) }
    }
}

// A small paste-trigger that fires on ⌘V of a file URL or plain text (macOS only).
private extension View {
    @ViewBuilder func pasteTrigger(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onPasteCommand(of: [.fileURL, .plainText]) { _ in action() }
        #else
        self
        #endif
    }
}

// MARK: - Small circular button (close, etc.)

struct NotebookCircleButton: View {
    let system: String
    var active: Bool = false
    var help: String = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(active ? Color.accentColor.opacity(0.15)
                                                  : Color.primary.opacity(hover ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(help)
    }
}
