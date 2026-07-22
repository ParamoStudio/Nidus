//
//  IdeasTool.swift
//  Nidus
//
//  Base tool — Ideas. Each idea is title + notes (Blueprint §2.4). The tile shows a numbered,
//  chronological list of titles with a discreet date subheader; a discreet button opens the
//  notes in a translucent panel (over a blurred backdrop) where they can be read and added to.
//

import SwiftUI

/// One idea parsed from a `## <date> — <title>` block and its note lines.
struct IdeaEntry: Identifiable {
    let id = UUID()
    let header: String   // full section title, used to locate the block in the file
    let date: String
    let title: String
    let notes: [String]
}

struct IdeasToolView: View {
    @Environment(NidusModel.self) private var model
    @Environment(WorkspaceOverlay.self) private var overlay
    @Environment(CardDragController.self) private var drag
    let context: ToolContext

    @State private var draft = ""
    @State private var flashID: String?

    private var fileURL: URL? { context.fileURL("ideas.md") }
    private var folderURL: URL? { context.folderURL }

    private var cards: [Card] {
        _ = model.fileChangeTick
        guard let fileURL else { return [] }
        return CardStore.read(from: fileURL)
    }

    var body: some View {
        VStack(spacing: 10) {
            ToolAddField(placeholder: "New idea…", text: $draft, onSubmit: addIdea)
            if cards.isEmpty {
                ToolEmptyHint("No ideas yet.")
            } else {
                RevealingList(slotID: context.slotID, ref: context.projectRef, flashID: $flashID) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(cards.reversed())) { card in
                            CardRow(card: card, folderURL: folderURL,
                                    sourceFile: fileURL, sourceTool: "ideas",
                                    toolIcon: Self.descriptor.icon, toolName: context.name,
                                    flashing: card.id == flashID) { expand(card) }
                                .id(card.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay(CardDropHighlight(active: fileURL != nil && drag.targetFile?.standardizedFileURL == fileURL?.standardizedFileURL))
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ToolFramePreferenceKey.self,
                    value: [ToolFrameInfo(fileURL: fileURL, toolID: "ideas",
                                          frame: geo.frame(in: .named("workspace")))])
            }
        )
    }

    private func expand(_ card: Card) {
        let url = fileURL
        let folder = folderURL
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                CardDetailView(card: card, fileURL: url, folderURL: folder,
                               toolIcon: Self.descriptor.icon, toolName: context.name) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }

    private func addIdea() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let fileURL else { return }
        CardStore.append(.make(title: title, origin: "ideas"), to: fileURL)
        draft = ""
        Haptics.tap()
        model.notifyFileChange()
    }
}

extension IdeasToolView {
    static let descriptor = ToolDescriptor(
        id: "ideas", title: "Ideas", defaultName: "Ideas",
        summary: "Developed notes — title + notes, dated. Duplicable & renamable.",
        icon: "lightbulb",
        validSizes: [.small, .wide, .medium, .large], files: ["ideas.md"],
        allowsMultiple: true,
        toolClass: .collector,
        accepts: [.generic, .task],
        quickAction: ToolQuickAction(defaultHotkey: "i", label: "Quick Idea", kind: .idea),
        makeView: { AnyView(IdeasToolView(context: $0)) }
    )
}

/// Translucent detail panel for an idea — read notes and add more.
struct IdeaDetailPanel: View {
    @Environment(NidusModel.self) private var model
    let entry: IdeaEntry
    let fileURL: URL?
    let onClose: () -> Void

    @State private var notes: [String]
    @State private var draft = ""

    init(entry: IdeaEntry, fileURL: URL?, onClose: @escaping () -> Void) {
        self.entry = entry
        self.fileURL = fileURL
        self.onClose = onClose
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.title3.weight(.semibold))
                    Text(entry.date).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.4)

            if notes.isEmpty {
                Text("No notes yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                            Text(note).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 280)
            }

            ToolAddField(placeholder: "Add a note…", text: $draft, onSubmit: addNote)
        }
        .padding(22)
        .frame(width: 420)
        .glassCard()
        .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
    }

    private func addNote() {
        let note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, let fileURL else { return }
        do {
            try MarkdownStore.appendNote(note, underSectionTitled: entry.header, in: fileURL)
            notes.insert(note, at: 0)
            draft = ""
            Haptics.tap()
            model.notifyFileChange()
        } catch { model.lastError = error.localizedDescription }
    }
}
