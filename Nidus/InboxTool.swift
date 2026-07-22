//
//  InboxTool.swift
//  Nidus
//
//  Base tool — Inbox. Raw capture (line + date), append-only, grouped by day (Blueprint §2.4).
//  Self-contained module: its view + its ToolDescriptor.
//

import SwiftUI

struct InboxToolView: View {
    @Environment(NidusModel.self) private var model
    @Environment(WorkspaceOverlay.self) private var overlay
    @Environment(CardDragController.self) private var drag
    let context: ToolContext

    @State private var draft = ""
    @State private var flashID: String?

    private var fileURL: URL? { context.fileURL("inbox.md") }
    private var folderURL: URL? { context.folderURL }

    /// Read straight from the file each render (keyed to fileChangeTick) — no @State list, so
    /// re-creating the view never flashes an empty state.
    private var cards: [Card] {
        _ = model.fileChangeTick
        guard let fileURL else { return [] }
        return CardStore.read(from: fileURL)
    }

    var body: some View {
        VStack(spacing: 8) {
            ToolAddField(placeholder: "Capture a thought…", text: $draft, onSubmit: capture)
            if cards.isEmpty {
                ToolEmptyHint("Nothing captured yet.")
            } else {
                RevealingList(slotID: context.slotID, ref: context.projectRef, flashID: $flashID) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(cards.reversed())) { card in
                            CardRow(card: card, folderURL: folderURL,
                                    sourceFile: fileURL, sourceTool: "inbox",
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
                    value: [ToolFrameInfo(fileURL: fileURL, toolID: "inbox",
                                          frame: geo.frame(in: .named("workspace")))])
            }
        )
    }

    private func capture() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let fileURL else { return }
        CardStore.append(.make(title: text, origin: "inbox"), to: fileURL)
        draft = ""
        model.notifyFileChange()
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
}

extension InboxToolView {
    static let descriptor = ToolDescriptor(
        id: "inbox", title: "Inbox", defaultName: "Inbox",
        summary: "Raw capture — everything lands here to be triaged.",
        icon: "tray",
        validSizes: [.small, .wide, .medium], files: ["inbox.md"],
        allowsMultiple: false,
        toolClass: .collector,
        accepts: [.generic, .task],
        makeView: { AnyView(InboxToolView(context: $0)) }
    )
}
