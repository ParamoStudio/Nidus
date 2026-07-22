//
//  TaskCardViews.swift
//  Nidus
//
//  Task flavour of the universal card. Same comfortable shape as the note cards, minus images and
//  plus what a task needs: a round complete toggle, coloured tags, a subnote, and a subtle deadline.
//   • `TaskCardFace`  — the compact cell (tags · round + title · subnote · date + deadline pill)
//   • `TaskCardRow`   — that cell wired for drag, double-click-to-open and a "…" menu
//   • `TaskDetailView`— the expanded editor (title, notes, tags, deadline), same language as Ideas
//

import SwiftUI

// MARK: - Compact cell

/// The task cell visual. `onToggle` completes (or, in the archive, un-completes) the task.
struct TaskCardFace: View {
    let card: Card
    let tags: [TaskTag]
    let isDone: Bool
    let onToggle: () -> Void

    private var subnote: String {
        card.body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }
    private var dateText: String {
        // In the archive (done) the relevant date is the completion date, not when it was created.
        let c = Calendar.current.dateComponents([.day, .month, .year], from: isDone ? card.modified : card.created)
        return String(format: "%02d/%02d/%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }
    /// The origin task-manager name, only for archived tasks.
    private var archiveOrigin: String { isDone ? (card.originName ?? "") : "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Top bar: tags and (in the archive) which list it came from — kept off the footer so
            // the date + deadline below have room to read whole.
            if !tags.isEmpty || !archiveOrigin.isEmpty {
                HStack(spacing: 6) {
                    if !tags.isEmpty { TagChips(tags: tags) }
                    if !archiveOrigin.isEmpty { originPill(archiveOrigin) }
                    Spacer(minLength: 0)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Button(action: onToggle) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                        // A hit area wider than the glyph, reserved for completing (never opens the card).
                        .frame(width: 30, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: -6)   // keep the glyph visually aligned despite the wider hit box
                .help(isDone ? "Mark as not done" : "Mark as done")
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .strikethrough(isDone, color: .secondary)
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !subnote.isEmpty {
                        Text(subnote)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
            }
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                Text(dateText).font(.caption2).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Spacer(minLength: 6)
                if let dl = card.deadline { DeadlinePill(deadline: dl) }
            }
            .frame(height: 13)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Which task manager a completed task came from (archive only).
    private func originPill(_ name: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "tray").font(.system(size: 8))
            Text(name).font(.caption2).lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// A row of small coloured tag pills.
struct TagChips: View {
    let tags: [TaskTag]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags) { t in
                Text(t.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TagPalette.color(t.color))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(TagPalette.color(t.color).opacity(0.16)))
                    .lineLimit(1)
            }
        }
    }
}

/// A subtle, non-alarming deadline pill (flag + short text).
struct DeadlinePill: View {
    let deadline: TaskDeadline
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag").font(.system(size: 9))
            Text(deadline.pillText).font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// A visible colour swatch that opens a popover of the 8 real colours (native menus render the
/// swatch symbols monochrome, so we use our own popover — the colour is actually visible).
struct TagColorDot: View {
    let color: Int
    var size: CGFloat = 13
    let onPick: (Int) -> Void
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            Circle().fill(TagPalette.color(color)).frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            HStack(spacing: 8) {
                ForEach(0..<TagPalette.count, id: \.self) { i in
                    Button { onPick(i); show = false } label: {
                        Circle().fill(TagPalette.color(i)).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(color == i ? 0.9 : 0.15),
                                                           lineWidth: color == i ? 2 : 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Row (drag + open + menu)

struct TaskCardRow: View {
    @Environment(NidusModel.self) private var model
    @Environment(CardDragController.self) private var drag

    let card: Card
    let folderURL: URL?
    var sourceFile: URL? = nil
    var sourceTool: String = ""
    var flashing: Bool = false
    let isDone: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var isBeingDragged: Bool { drag.dragging?.card.id == card.id }
    private var tags: [TaskTag] { model.tags(ids: card.tagIDs) }

    var body: some View {
        TaskCardFace(card: card, tags: tags, isDone: isDone, onToggle: onToggle)
            .overlay(alignment: .topTrailing) { ellipsisMenu }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.09 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(flashing ? 0.9 : 0), lineWidth: 2))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .animation(.easeOut(duration: 0.25), value: flashing)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isBeingDragged ? 0.25 : 1)
            .onHover { hovering = $0 }
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
                        } else { drag.move(to: value.location) }
                    }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.18)) { drag.drop(model: model) } }
            )
            // Single click opens — but as a plain `.onTapGesture` (NOT `.simultaneousGesture`) so the
            // completion circle and the "…" menu consume their own taps instead of also opening the card.
            .onTapGesture { onOpen() }
    }

    private var ellipsisMenu: some View {
        Menu {
            Button { onOpen() } label: { Label("Open", systemImage: "arrow.up.left.and.arrow.down.right") }
            Button(role: .destructive) { onDelete() } label: { Label("Delete task", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.regularMaterial).opacity(hovering ? 1 : 0))
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .opacity(hovering ? 1 : 0)
        .padding(6)
    }
}

// MARK: - Expanded editor

/// The task editor — same feel as the Ideas card popup, adapted: title + round complete, a notes
/// subnote (auto-grows to 8 lines), tags (bank + colour), and a Day/Week/Month deadline + note.
struct TaskDetailView: View {
    @Environment(NidusModel.self) private var model
    let card: Card
    let fileURL: URL?
    let folderURL: URL?
    var toolIcon: String = ""
    var toolName: String = ""
    let isDone: Bool
    var editable: Bool = true      // Task Archive opens a read-only viewer.
    let onToggle: () -> Void      // complete / un-complete (also closes)
    let onClose: () -> Void

    @State private var title: String
    @State private var subnote: String
    @State private var tagIDs: [String]
    @State private var scope: DeadlineScope?      // nil = no deadline
    @State private var dueDate: Date
    @State private var newTag: String = ""
    @State private var deleted = false
    @State private var showTagManager = false
    @FocusState private var rootFocused: Bool

    init(card: Card, fileURL: URL?, folderURL: URL?, toolIcon: String = "", toolName: String = "",
         isDone: Bool, editable: Bool = true,
         onToggle: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.card = card; self.fileURL = fileURL; self.folderURL = folderURL
        self.toolIcon = toolIcon; self.toolName = toolName
        self.isDone = isDone; self.editable = editable
        self.onToggle = onToggle; self.onClose = onClose
        _title = State(initialValue: card.title)
        _subnote = State(initialValue: card.body)
        _tagIDs = State(initialValue: card.tagIDs)
        _scope = State(initialValue: card.deadline?.scope)
        _dueDate = State(initialValue: card.deadline?.date ?? Date())
    }

    private var tags: [TaskTag] { model.tags(ids: tagIDs) }
    private var hasDeadline: Bool { scope != nil }
    private var subnoteEmpty: Bool { subnote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Grows to exactly fit its content — everything always fits, no scroll.
            VStack(alignment: .leading, spacing: 18) {
                titleRow
                if !editable { originLine }
                if editable || !subnoteEmpty { section("Notes") { notesBlock } }
                if editable || !tags.isEmpty { tagsSection }
                if editable || hasDeadline { section("Deadline") { deadlineBlock } }
                HStack { Spacer(); deleteButton }
            }
            .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 4)
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .glassCard()
        .contentShape(Rectangle())
        // Swallow empty-chrome taps (coexists with the text fields via simultaneousGesture).
        .simultaneousGesture(TapGesture().onEnded {})
        .background(Button("", action: close).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
        .focusable()
        .focusEffectDisabled()
        .focused($rootFocused)
        .onAppear { rootFocused = true }
        .onDisappear { if editable && !deleted { save() } }
        .sheet(isPresented: $showTagManager) { TagManagerView() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: toolIcon.isEmpty ? "checklist" : toolIcon)
                .font(.title3).foregroundStyle(.secondary)
            Text(toolName.isEmpty ? "Task" : toolName)
                .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            circleButton("xmark", action: close)
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 10)
    }

    @ViewBuilder private var titleRow: some View {
        if editable {
            HStack(alignment: .top, spacing: 11) {
                Button { save(); onToggle() } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isDone ? "Mark as not done" : "Mark as done")
                TextField("Task", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold))
            }
        } else {
            // Read-only viewer (archive): just the title, struck through if done.
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .strikethrough(isDone, color: .secondary)
                .foregroundStyle(isDone ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Archive viewer: where it came from + the day it was completed.
    private var originLine: some View {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: card.modified)
        let ds = String(format: "%02d/%02d/%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
        return HStack(spacing: 8) {
            if let o = card.originName, !o.isEmpty {
                Label(o, systemImage: "tray").font(.caption)
                Text("·").font(.caption).foregroundStyle(.tertiary)
            }
            Text("Completed \(ds)").font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: Notes (a short one-liner — Enter saves & closes; capped, no paragraphs)

    @ViewBuilder private var notesBlock: some View {
        if editable { notesEditor } else { notesStatic }
    }

    private static let notesLimit = 80

    private var notesEditor: some View {
        TextField("Notes", text: $subnote)
            .textFieldStyle(.plain).font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(panelBackground)
            .onSubmit { close() }               // Enter = done → save + close (notes are one-liners)
            .onChange(of: subnote) {
                var v = subnote.replacingOccurrences(of: "\n", with: " ")
                if v.count > Self.notesLimit { v = String(v.prefix(Self.notesLimit)) }
                if v != subnote { subnote = v }
            }
    }

    private var notesStatic: some View {
        Text(subnote)
            .font(.callout).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(panelBackground)
    }

    // MARK: Tags (shared bank + colour)

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags").font(.caption.weight(.semibold)).textCase(.uppercase)
                    .tracking(1).foregroundStyle(.secondary)
                Spacer()
                if editable {
                    Button { showTagManager = true } label: {
                        Image(systemName: "gearshape").font(.caption).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain).help("Manage tags (rename, recolour, delete)")
                }
            }
            tagsBlock
        }
    }

    @ViewBuilder private var tagsBlock: some View {
        if editable {
            tagsEditor
        } else if tags.isEmpty {
            Text("No tags").font(.callout).foregroundStyle(.tertiary)
        } else {
            FlowRow(spacing: 6) {
                ForEach(tags) { t in
                    Text(t.name).font(.caption.weight(.medium))
                        .foregroundStyle(TagPalette.color(t.color))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(TagPalette.color(t.color).opacity(0.16)))
                }
            }
        }
    }

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(tags) { tag in tagChip(tag) }
                }
            }
            tagAddField
        }
    }

    private func tagChip(_ tag: TaskTag) -> some View {
        HStack(spacing: 7) {
            TagColorDot(color: tag.color, size: 13) { model.setTagColor(tag.id, to: $0) }
            Text(tag.name).font(.caption.weight(.medium))
            Button { tagIDs.removeAll { $0 == tag.id } } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(TagPalette.color(tag.color).opacity(0.16)))
    }

    private var tagAddField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "tag").font(.caption).foregroundStyle(.secondary)
                TextField("Add a tag…", text: $newTag).textFieldStyle(.plain).font(.callout)
                    .onSubmit(commitTag)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(panelBackground)

            // Autocomplete from the shared bank.
            let suggestions = model.tagSuggestions(matching: newTag, excluding: tagIDs)
            if !newTag.trimmingCharacters(in: .whitespaces).isEmpty && !suggestions.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(suggestions.prefix(8)) { tag in
                        Button { tagIDs.append(tag.id); newTag = "" } label: {
                            HStack(spacing: 5) {
                                Circle().fill(TagPalette.color(tag.color)).frame(width: 8, height: 8)
                                Text(tag.name).font(.caption)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func commitTag() {
        guard let tag = model.createOrFindTag(named: newTag) else { return }
        if !tagIDs.contains(tag.id) { tagIDs.append(tag.id) }
        newTag = ""
    }

    // MARK: Deadline (own calendar: click = day, double-click = week, double-click month = month)

    @ViewBuilder private var deadlineBlock: some View {
        if editable { deadlineEditor } else { deadlineStatic }
    }

    private var deadlineEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeadlineCalendar(scope: $scope, date: $dueDate)
            HStack(spacing: 8) {
                if let s = scope {
                    DeadlinePill(deadline: TaskDeadline(date: dueDate, scope: s))
                } else {
                    Text("No deadline").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                if scope != nil {
                    Button("Clear") { scope = nil }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var deadlineStatic: some View {
        if let s = scope {
            DeadlinePill(deadline: TaskDeadline(date: dueDate, scope: s))
        } else {
            Text("No deadline").font(.callout).foregroundStyle(.tertiary)
        }
    }

    // MARK: Chrome

    private var deleteButton: some View {
        Button(action: deleteTask) {
            Label("Delete task", systemImage: "trash")
                .font(.callout.weight(.medium)).foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14)))
        }.buttonStyle(.plain)
    }

    private func section<C: View>(_ heading: String, @ViewBuilder _ inner: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.caption.weight(.semibold)).textCase(.uppercase)
                .tracking(1).foregroundStyle(.secondary)
            inner()
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
    }

    private func circleButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }.buttonStyle(.plain)
    }

    // MARK: Actions

    private func save() {
        guard editable, let fileURL else { return }
        var updated = card
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = t.isEmpty ? card.title : t
        updated.body = subnote
        updated.tagIDs = tagIDs
        if let scope { updated.deadline = TaskDeadline(date: dueDate, scope: scope) }
        else { updated.deadline = nil }
        CardStore.update(updated, in: fileURL)
        model.notifyFileChange()
    }

    private func close() { save(); onClose() }

    private func deleteTask() {
        deleted = true
        if let fileURL {
            CardStore.remove(id: card.id, from: fileURL)
            model.notifyFileChange()
        }
        onClose()
    }
}

// MARK: - Deadline calendar (in the app's style, ingrained in the card)

/// A month grid. Click a day → that day. Click another → change. Double-click a day → its whole
/// week. Double-click the month name → the whole month. Prev/next arrows change month.
struct DeadlineCalendar: View {
    @Binding var scope: DeadlineScope?
    @Binding var date: Date
    @State private var month: Date

    private let cal = Calendar.current

    init(scope: Binding<DeadlineScope?>, date: Binding<Date>) {
        _scope = scope; _date = date
        let base = date.wrappedValue
        let c = Calendar.current
        _month = State(initialValue: c.date(from: c.dateComponents([.year, .month], from: base)) ?? base)
    }

    private var monthIsSelected: Bool {
        scope == .month && cal.isDate(month, equalTo: date, toGranularity: .month)
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            grid
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08)))
    }

    private var header: some View {
        HStack {
            arrow("chevron.left") { shift(-1) }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.callout.weight(.semibold))
                .foregroundStyle(monthIsSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(monthIsSelected ? 0.14 : 0)))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { selectMonth() }
                .help("Double-click to set the whole month")
            Spacer()
            arrow("chevron.right") { shift(1) }
        }
    }

    private func arrow(_ system: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: system).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var grid: some View {
        let firstOfMonth = month
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = (cal.component(.weekday, from: firstOfMonth) + 5) % 7  // Monday-first
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 3), count: 7)
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { off, ch in
                Text(String(ch)).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary).id("wd\(off)")
            }
            ForEach(0..<leading, id: \.self) { i in Color.clear.frame(height: 28).id("blank\(i)") }
            ForEach(1...daysInMonth, id: \.self) { day in
                dayCell(day).id("day\(day)")
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let d = cal.date(byAdding: .day, value: day - 1, to: month) ?? month
        let isDay = scope == .day && cal.isDate(d, inSameDayAs: date)
        let isWeek = scope == .week && cal.isDate(cal.startOfWeek(for: d), inSameDayAs: cal.startOfWeek(for: date))
        let isToday = cal.isDateInToday(d)
        let selected = isDay || isWeek || monthIsSelected
        return Text("\(day)")
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(selected ? Color.white : (isToday ? .primary : .secondary))
            .background {
                if isDay { Circle().fill(Color.accentColor).frame(width: 28, height: 28) }
                else if isWeek { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.85)) }
                else if monthIsSelected { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.7)) }
                else if isToday { Circle().strokeBorder(Color.secondary.opacity(0.5)).frame(width: 28, height: 28) }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { scope = .week; date = d }
            .onTapGesture(count: 1) {
                // Clicking the already-selected day clears the deadline (no need for the Clear button).
                if scope == .day && cal.isDate(d, inSameDayAs: date) { scope = nil }
                else { scope = .day; date = d }
            }
    }

    private func selectMonth() { scope = .month; date = month }
    private func shift(_ n: Int) {
        withAnimation(.easeOut(duration: 0.15)) { month = cal.date(byAdding: .month, value: n, to: month) ?? month }
    }
}

// MARK: - Tag manager (the "hidden in settings" door to rename / recolour / delete)

/// A small manager to fix tag mistakes: rename, change colour, or delete a tag from the bank.
struct TagManagerView: View {
    @Environment(NidusModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage tags").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            if model.allTags.isEmpty {
                Spacer()
                Text("No tags yet.").font(.callout).foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.allTags) { tag in TagManagerRow(tag: tag) }
                    }
                    .padding(16)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(width: 380, height: 440)
    }
}

private struct TagManagerRow: View {
    @Environment(NidusModel.self) private var model
    let tag: TaskTag
    @State private var name: String

    init(tag: TaskTag) { self.tag = tag; _name = State(initialValue: tag.name) }

    var body: some View {
        HStack(spacing: 10) {
            TagColorDot(color: tag.color, size: 16) { model.setTagColor(tag.id, to: $0) }
            TextField("Name", text: $name)
                .textFieldStyle(.plain).font(.callout)
                .onSubmit { model.renameTag(tag.id, to: name) }
            Spacer()
            Button(role: .destructive) { model.deleteTag(tag.id) } label: {
                Image(systemName: "trash").font(.callout).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - A simple wrapping row (chips flow onto new lines)

struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
