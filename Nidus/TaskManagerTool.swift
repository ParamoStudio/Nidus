//
//  TaskManagerTool.swift
//  Nidus
//
//  Base tool — Task Manager. Active tasks as cards (round complete toggle, tags, subnote, deadline).
//  Completing one moves its card to the project's shared `tasks-done.md` (the Task Archive).
//

import SwiftUI

struct TaskManagerToolView: View {
    @Environment(NidusModel.self) private var model
    @Environment(WorkspaceOverlay.self) private var overlay
    @Environment(CardDragController.self) private var drag
    let context: ToolContext

    @State private var draft = ""
    @State private var flashID: String?

    private var fileURL: URL? { context.fileURL("tasks-todo.md") }
    private var folderURL: URL? { context.folderURL }
    /// The project's single archive file, shared by every task manager here.
    private var archiveURL: URL? { context.folderURL?.appendingPathComponent("tasks-done.md") }
    private var toolIcon: String { TaskManagerToolView.descriptor.icon }
    private var toolName: String { context.name.isEmpty ? TaskManagerToolView.descriptor.defaultName : context.name }

    private var cards: [Card] {
        _ = model.fileChangeTick
        guard let fileURL else { return [] }
        return CardStore.read(from: fileURL)
    }

    var body: some View {
        VStack(spacing: 8) {
            ToolAddField(placeholder: "Add task…", text: $draft, onSubmit: addTask)
            if cards.isEmpty {
                ToolEmptyHint("No active tasks.")
            } else {
                RevealingList(slotID: context.slotID, ref: context.projectRef, flashID: $flashID) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(cards.reversed())) { card in
                            TaskCardRow(card: card, folderURL: folderURL,
                                        sourceFile: fileURL, sourceTool: "task-manager",
                                        flashing: card.id == flashID,
                                        isDone: false,
                                        onToggle: { complete(card) },
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
        .contentShape(Rectangle())
        .overlay(CardDropHighlight(active: fileURL != nil && drag.targetFile?.standardizedFileURL == fileURL?.standardizedFileURL))
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ToolFramePreferenceKey.self,
                    value: [ToolFrameInfo(fileURL: fileURL, toolID: "task-manager",
                                          frame: geo.frame(in: .named("workspace")))])
            }
        )
    }

    private func addTask() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let fileURL else { return }
        CardStore.append(.make(title: text, origin: "task-manager"), to: fileURL)
        draft = ""
        Haptics.tap()
        model.notifyFileChange()
    }

    /// Move the (freshly saved) task to the archive, remembering the file it came from.
    private func complete(_ card: Card) {
        guard let fileURL, let archiveURL else { return }
        guard var c = CardStore.read(from: fileURL).first(where: { $0.id == card.id }) else { return }
        c.originFile = fileURL.lastPathComponent
        c.originName = toolName          // so the archive can show where it came from
        c.modified = Date()              // completion date (shown in the archive)
        CardStore.remove(id: card.id, from: fileURL)
        CardStore.append(c, to: archiveURL)
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
                               toolIcon: toolIcon, toolName: toolName, isDone: false,
                               onToggle: {
                                   withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                                   complete(card)
                               },
                               onClose: { withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() } })
            }
        }
    }
}

extension TaskManagerToolView {
    static let descriptor = ToolDescriptor(
        id: "task-manager", title: "Task Manager", defaultName: "Task Manager",
        summary: "Active tasks with tags and deadlines; completing one archives it.",
        icon: "checklist",
        validSizes: [.small, .wide, .medium, .large], files: ["tasks-todo.md", "tasks-done.md"],
        allowsMultiple: true,
        toolClass: .worker,
        accepts: [.generic, .task],
        produces: .task,
        actions: [ToolAction(id: "complete", title: "Complete", icon: "checkmark.circle")],
        quickAction: ToolQuickAction(defaultHotkey: "t", label: "Quick Task", kind: .task),
        makeView: { AnyView(TaskManagerToolView(context: $0)) }
    )
}
