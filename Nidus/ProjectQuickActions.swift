//
//  ProjectQuickActions.swift
//  Nidus
//
//  The row of up to three user shortcuts on the project card. Outside Customize Mode only the
//  configured ones show (centred). In Customize Mode three slots appear; an empty slot reads
//  "Configure quick action" and tapping any slot opens a small editor (open an app, a web URL, or
//  a file/folder + a title). Actions are stored per-project in nidus.json.
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectQuickActions: View {
    let actions: [QuickAction]
    let isEditing: Bool
    /// Run a configured action (outside Customize).
    let onRun: (QuickAction) -> Void
    /// Persist the new full list (the workspace forwards this to the model).
    let onChange: ([QuickAction]) -> Void
    /// If this project is a fork, its origin — shown as a reserved (non-editable) "Forked Original" pill
    /// that opens the original. It occupies one of the three slots, leaving two for the user.
    var forkedOriginal: ProjectRef? = nil
    var onOpenOriginal: (ProjectRef) -> Void = { _ in }
    /// Projects forked FROM this one — shown as a reserved "Forks" dropdown to jump to any of them
    /// (GitHub-style), also occupying a slot.
    var forks: [ProjectHit] = []
    var onOpenFork: (ProjectRef) -> Void = { _ in }

    @State private var editingIndex: Int?

    private let maxActions = 3
    private var reservedCount: Int { (forkedOriginal != nil ? 1 : 0) + (forks.isEmpty ? 0 : 1) }
    /// User-configurable slots left once the reserved pills (Forked Original / Forks) take theirs.
    private var userSlots: Int { max(0, maxActions - reservedCount) }

    @ViewBuilder private var reservedPills: some View {
        if forkedOriginal != nil { forkedOriginalPill }
        if !forks.isEmpty { forksPill }
    }

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 10) {
                    reservedPills
                    ForEach(0..<userSlots, id: \.self) { i in
                        configureSlot(i)
                    }
                }
            } else if reservedCount > 0 || !actions.isEmpty {
                HStack(spacing: 10) {
                    reservedPills
                    ForEach(actions.prefix(userSlots)) { action in
                        Button { onRun(action) } label: { pillBody(action.title, icon: icon(for: action.kind)) }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                }
            }
        }
        .popover(isPresented: Binding(get: { editingIndex != nil },
                                      set: { if !$0 { editingIndex = nil } })) {
            QuickActionEditor(
                existing: (editingIndex ?? 0) < actions.count ? actions[editingIndex ?? 0] : nil,
                onSave: { commit($0) },
                onRemove: { remove() }
            )
        }
    }

    /// The reserved pill that opens the project this one was forked from. Not editable.
    private var forkedOriginalPill: some View {
        Button { if let o = forkedOriginal { onOpenOriginal(o) } } label: {
            pillBody("Forked Original", icon: "arrow.triangle.branch")
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Open the project this one was forked from")
    }

    /// The reserved "Forks" dropdown — lists projects forked from this one; pick one to jump to it.
    private var forksPill: some View {
        Menu {
            ForEach(forks) { fork in
                Button(fork.project.name) { onOpenFork(fork.ref) }
            }
        } label: {
            pillBody("Forks · \(forks.count)", icon: "arrow.triangle.branch")
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Projects forked from this one")
    }

    @ViewBuilder
    private func configureSlot(_ i: Int) -> some View {
        let action = i < actions.count ? actions[i] : nil
        Button { editingIndex = i } label: {
            if let action {
                pillBody(action.title, icon: icon(for: action.kind))
                    .glassEffect(.regular.interactive(), in: Capsule())
            } else {
                pillBody("Configure quick action", icon: "plus", muted: true)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.4),
                                                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
        }
        .buttonStyle(.plain)
    }

    private func pillBody(_ title: String, icon: String, muted: Bool = false) -> some View {
        Label(title, systemImage: icon)
            .font(.callout.weight(muted ? .regular : .medium))
            .foregroundStyle(muted ? .secondary : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .contentShape(Capsule())
    }

    private func icon(for kind: QuickAction.Kind) -> String {
        switch kind {
        case .app: return "app"
        case .web: return "globe"
        case .route: return "folder"
        case .script: return "terminal"
        }
    }

    private func commit(_ action: QuickAction) {
        guard let i = editingIndex else { return }
        var updated = actions
        if i < updated.count { updated[i] = action } else { updated.append(action) }
        onChange(updated)
        editingIndex = nil
    }

    private func remove() {
        guard let i = editingIndex, i < actions.count else { editingIndex = nil; return }
        var updated = actions
        updated.remove(at: i)
        onChange(updated)
        editingIndex = nil
    }
}

/// Small editor: title + kind (App / Web / File) + target (URL field or a file picker).
private struct QuickActionEditor: View {
    let existing: QuickAction?
    let onSave: (QuickAction) -> Void
    let onRemove: () -> Void

    @State private var title = ""
    @State private var kind: QuickAction.Kind = .web
    @State private var target = ""
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick action").font(.headline)

            TextField("Title", text: $title).textFieldStyle(.roundedBorder)

            Picker("", selection: $kind) {
                Text("App").tag(QuickAction.Kind.app)
                Text("Web").tag(QuickAction.Kind.web)
                Text("Route").tag(QuickAction.Kind.route)
                Text("Script").tag(QuickAction.Kind.script)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if kind == .web {
                TextField("https://…", text: $target).textFieldStyle(.roundedBorder)
            } else {
                Button { importing = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: chooseIcon)
                        Text(target.isEmpty ? choosePrompt
                             : URL(fileURLWithPath: target).lastPathComponent)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack {
                if existing != nil {
                    Button("Remove", role: .destructive) { onRemove() }
                }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 290)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: importTypes,
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                target = url.path
                if title.trimmingCharacters(in: .whitespaces).isEmpty {
                    title = url.deletingPathExtension().lastPathComponent
                }
            }
        }
        .onAppear {
            if let e = existing { title = e.title; kind = e.kind; target = e.target }
        }
    }

    private var chooseIcon: String {
        switch kind {
        case .app: return "app"
        case .route: return "folder"
        case .script: return "terminal"
        case .web: return "globe"
        }
    }

    private var choosePrompt: String {
        switch kind {
        case .app: return "Choose app…"
        case .route: return "Choose file or folder…"
        case .script: return "Choose script…"
        case .web: return ""
        }
    }

    /// `.route` allows BOTH files and folders (.folder makes the panel let you *select* a folder
    /// instead of only navigating into it). `.script` is any file — we execute it, not open it.
    private var importTypes: [UTType] {
        switch kind {
        case .app: return [.application]
        case .route: return [.item, .folder]
        case .script: return [.item]
        case .web: return [.item]
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !target.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        guard canSave else { return }
        onSave(QuickAction(id: existing?.id ?? UUID().uuidString,
                           title: title.trimmingCharacters(in: .whitespaces),
                           kind: kind,
                           target: target.trimmingCharacters(in: .whitespaces)))
    }
}
