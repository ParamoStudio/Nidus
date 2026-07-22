//
//  TaskArchiveTool.swift
//  Nidus
//
//  Base tool — Task Archive. Completed tasks as (checked) cards. Un-checking one sends it back to
//  the task manager it came from. Singleton: a single archive collects from every task manager.
//

import SwiftUI

struct TaskArchiveToolView: View {
    @Environment(NidusModel.self) private var model
    @Environment(WorkspaceOverlay.self) private var overlay
    let context: ToolContext

    @State private var flashID: String?

    private var fileURL: URL? { context.fileURL("tasks-done.md") }
    private var folderURL: URL? { context.folderURL }
    private var toolIcon: String { TaskArchiveToolView.descriptor.icon }
    private var toolName: String { context.name.isEmpty ? TaskArchiveToolView.descriptor.defaultName : context.name }

    private var cards: [Card] {
        _ = model.fileChangeTick
        guard let fileURL else { return [] }
        return CardStore.read(from: fileURL)
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ToolEmptyHint("Nothing completed yet.")
            } else {
                RevealingList(slotID: context.slotID, ref: context.projectRef, flashID: $flashID) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(cards.reversed())) { card in
                            // sourceFile nil → not draggable; only the round toggle sends it back.
                            TaskCardRow(card: card, folderURL: folderURL,
                                        sourceFile: nil, sourceTool: "task-archive",
                                        flashing: card.id == flashID,
                                        isDone: true,
                                        onToggle: { restore(card) },
                                        onOpen: { expand(card) },
                                        onDelete: { deleteTask(card) })
                                .id(card.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Send a completed task back to the task manager it came from.
    private func restore(_ card: Card) {
        guard let fileURL, let folderURL else { return }
        guard var c = CardStore.read(from: fileURL).first(where: { $0.id == card.id }) else { return }
        let dest = folderURL.appendingPathComponent(c.originFile ?? "tasks-todo.md")
        c.originFile = nil
        c.originName = nil
        c.modified = Date()
        CardStore.remove(id: card.id, from: fileURL)
        CardStore.append(c, to: dest)
        model.notifyFileChange()
        Haptics.tap()
    }

    private func deleteTask(_ card: Card) {
        guard let fileURL else { return }
        CardStore.remove(id: card.id, from: fileURL)
        model.notifyFileChange()
    }

    private func expand(_ card: Card) {
        let url = fileURL; let folder = folderURL
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                TaskDetailView(card: card, fileURL: url, folderURL: folder,
                               toolIcon: toolIcon, toolName: toolName, isDone: true, editable: false,
                               onToggle: {
                                   withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                                   restore(card)
                               },
                               onClose: { withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() } })
            }
        }
    }
}

extension TaskArchiveToolView {
    static let descriptor = ToolDescriptor(
        id: "task-archive", title: "Task Archive", defaultName: "Task Archive",
        summary: "Completed tasks; un-check one to send it back where it came from.",
        icon: "checkmark.circle",
        validSizes: [.small, .wide, .medium], files: ["tasks-done.md"],
        allowsMultiple: false, // singleton: a single archive collects from all task managers
        toolClass: .archive,
        accepts: [], // not a drag target — only reached by completing a task
        produces: .task,
        makeView: { AnyView(TaskArchiveToolView(context: $0)) }
    )
}
