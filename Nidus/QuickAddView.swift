//
//  QuickAddView.swift
//  Nidus
//
//  Quick capture into the active project: ⌘I (idea) / ⌘T (task) — Blueprint §4.3.
//  A small focused prompt; submit appends to the project's .md and closes.
//

import SwiftUI

enum QuickAddKind: Identifiable {
    case idea, task
    var id: Int { self == .idea ? 0 : 1 }

    var title: LocalizedStringKey { self == .idea ? "Quick idea" : "Quick task" }
    var placeholder: LocalizedStringKey { self == .idea ? "New idea…" : "New task…" }
    var icon: String { self == .idea ? "lightbulb" : "checklist" }
}

struct QuickAddView: View {
    @Environment(NidusModel.self) private var model
    let kind: QuickAddKind
    /// The resolved `.md` of the specific tool INSTANCE this capture targets (so a duplicated tool
    /// with its own hotkey writes to its own file).
    let fileURL: URL?
    /// The target tool's id (used as the created card's `origin`).
    var tool: String = ""
    /// The target instance's display name — inherited into the header ("Quick <name>") so the prompt
    /// reads as the tool you actually pressed (e.g. "Quick Recipes"), not a hardcoded kind.
    var toolName: String = ""
    let onClose: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    /// "Recipes" if the instance is named, else a generic fallback for the kind.
    private var displayName: String {
        toolName.isEmpty ? (kind == .idea ? "idea" : "task") : toolName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Quick \(displayName)")
            } icon: {
                Image(systemName: kind.icon)
            }
            .font(.headline)
            // One versatile prompt for any tool — the header already says which one.
            TextField("Add a new entry to the active project…", text: $text)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit(submit)
                #if os(iOS)
                .autocorrectionDisabled()
                #endif
        }
        .padding(20)
        .frame(width: 460)
        .glassCard()
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
        .onAppear { focused = true }
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let fileURL else { onClose(); return }
        do {
            switch kind {
            case .idea: CardStore.append(.make(title: value, origin: tool), to: fileURL)
            case .task: try MarkdownStore.addTask(value, toTodo: fileURL)
            }
            Haptics.tap()
            model.notifyFileChange()
        } catch { model.lastError = error.localizedDescription }
        onClose()
    }
}
