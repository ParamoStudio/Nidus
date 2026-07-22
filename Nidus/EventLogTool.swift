//
//  EventLogTool.swift
//  Nidus
//
//  Event Log — a light, visual "git" for a project: a chronological log of decisions, iterations,
//  milestones and abandoned branches, so the WHY behind choices stays legible. Each event reuses the
//  universal Card (title + notes + images) plus extras: a user-set date/time (the timeline key), a
//  fixed event TYPE with its colour, and an optional PARENT (which event this one branches from —
//  the lineage). The tile is a compact, inviting timeline; the tool is worth more open — "View all
//  events" expands into a two-pane browser/editor.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Event type (the coloured dot)

enum EventType: String, CaseIterable, Identifiable {
    case decision, iteration, milestone, abandoned
    var id: String { rawValue }

    var label: String {
        switch self {
        case .decision:  return "Decision"
        case .iteration: return "Iteration"
        case .milestone: return "Milestone"
        case .abandoned: return "Abandoned"
        }
    }
    /// Muted, flat colours in keeping with the rest of the app.
    var color: Color {
        switch self {
        case .decision:  return Color(hex: "5B7FE0")
        case .iteration: return Color(hex: "D6A24B")
        case .milestone: return Color(hex: "57A177")
        case .abandoned: return Color(hex: "B06A6A")
        }
    }
    var icon: String {
        switch self {
        case .decision:  return "checkmark.seal"
        case .iteration: return "arrow.triangle.2.circlepath"
        case .milestone: return "flag.fill"
        case .abandoned: return "arrow.triangle.branch"
        }
    }

    /// Milestone and Abandoned are ENDPOINTS — they close a branch. So they can only hang off a live
    /// event (a Decision or Iteration): no milestone-of-a-milestone, no abandoning an achievement or an
    /// already-abandoned branch. Decisions/iterations can branch from anything. That's the whole ruleset.
    var isEndpoint: Bool { self == .milestone || self == .abandoned }
    static func canParent(child: EventType, parent: EventType) -> Bool {
        child.isEndpoint ? (parent == .decision || parent == .iteration) : true
    }
}

// MARK: - Model layer (Card + extras)

enum EventLog {
    static let dateKey = "eventDate"
    static let typeKey = "eventType"
    static let parentKey = "parent"     // id of the event this one branches from (iteration/milestone of…)

    private static let iso = ISO8601DateFormatter()
    private static let dateFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f }()
    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    struct Event: Identifiable {
        let card: Card
        var id: String { card.id }
        let date: Date
        let type: EventType
        let parent: String?     // id of the event this branches from (nil = a root)
        var title: String { card.title }
        var notes: String { card.body }
        var images: [String] { card.images }
    }

    static func events(from url: URL?) -> [Event] {
        guard let url else { return [] }
        return CardStore.read(from: url).map { card in
            let date = card.extra[dateKey].flatMap { iso.date(from: $0) } ?? card.created
            let type = card.extra[typeKey].flatMap { EventType(rawValue: $0) } ?? .decision
            let parent = card.extra[parentKey].flatMap { $0.isEmpty ? nil : $0 }
            return Event(card: card, date: date, type: type, parent: parent)
        }
        .sorted { $0.date > $1.date }   // newest first
    }

    /// All ids in the same thread as `id`: walk to the root, then collect every descendant of it.
    static func thread(of id: String, in events: [Event]) -> Set<String> {
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        // Root of this event's chain (guard against loops).
        var root = id, seen: Set<String> = []
        while let p = byID[root]?.parent, byID[p] != nil, !seen.contains(root) { seen.insert(root); root = p }
        // Everything whose ancestor chain reaches root.
        func reachesRoot(_ e: Event) -> Bool {
            var cur: String? = e.id, guardSet: Set<String> = []
            while let c = cur, !guardSet.contains(c) {
                if c == root { return true }
                guardSet.insert(c); cur = byID[c]?.parent
            }
            return false
        }
        return Set(events.filter(reachesRoot).map(\.id))
    }

    /// The colour of a thread = the type colour of its root event (the decision it stems from).
    static func rootColor(of id: String, in events: [Event]) -> Color {
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        var root = id, seen: Set<String> = []
        while let p = byID[root]?.parent, byID[p] != nil, !seen.contains(root) { seen.insert(root); root = p }
        return byID[root]?.type.color ?? .accentColor
    }

    /// Ids that can't be a parent of `editingID` (itself + its descendants) — prevents cycles.
    static func invalidParents(for editingID: String?, in events: [Event]) -> Set<String> {
        guard let editingID else { return [] }
        let byParent = Dictionary(grouping: events, by: { $0.parent ?? "" })
        var out: Set<String> = [editingID]
        var stack = [editingID]
        while let cur = stack.popLast() {
            for child in byParent[cur] ?? [] where !out.contains(child.id) {
                out.insert(child.id); stack.append(child.id)
            }
        }
        return out
    }

    static func dateLine(_ date: Date) -> String {
        let c = Calendar.current
        // A day-only date (no meaningful time) is stored at 00:00 — show just the date then.
        if c.component(.hour, from: date) == 0 && c.component(.minute, from: date) == 0 {
            return dateFmt.string(from: date)
        }
        return "\(dateFmt.string(from: date)) · \(timeFmt.string(from: date))"
    }

    /// Builds a Card carrying the event's extras (used for both add and update).
    static func makeCard(id: String?, title: String, notes: String, date: Date, type: EventType,
                         images: [String], parent: String?) -> Card {
        var card = id != nil
            ? Card(id: id!, title: title, body: notes, images: images, links: [],
                   created: Date(), modified: Date(), origin: "event-log", extra: [:])
            : Card.make(title: title, body: notes, origin: "event-log")
        card.title = title
        card.body = notes
        card.images = images
        card.extra[dateKey] = iso.string(from: date)
        card.extra[typeKey] = type.rawValue
        card.extra[parentKey] = parent ?? ""
        return card
    }
}

// MARK: - Tile (closed view)

struct EventLogToolView: View {
    @Environment(NidusModel.self) private var model
    @Environment(WorkspaceOverlay.self) private var overlay
    let context: ToolContext

    @State private var hoverID: String?

    private var fileURL: URL? { context.fileURL("event-log.md") }
    private var folderURL: URL? { context.folderURL }
    private var events: [EventLog.Event] { _ = model.fileChangeTick; return EventLog.events(from: fileURL) }

    var body: some View {
        VStack(spacing: 8) {
            if events.isEmpty {
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Text("No events yet.").font(.caption).foregroundStyle(.tertiary)
                    Button { open(selecting: nil, add: true) } label: {
                        Label("Add first event", systemImage: "plus")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TidyScroll {
                    let list = events
                    // A little extra: hovering a row lights up its whole thread here too.
                    let thread = hoverID.map { EventLog.thread(of: $0, in: list) } ?? []
                    let spine = hoverID.map { EventLog.rootColor(of: $0, in: list) } ?? .accentColor
                    let idxs = list.enumerated().filter { thread.contains($0.element.id) }.map(\.offset)
                    let spanMin = idxs.min() ?? 0, spanMax = idxs.max() ?? 0
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { idx, ev in
                            let member = thread.contains(ev.id)
                            TimelineRow(event: ev, folderURL: folderURL, isLast: idx == list.count - 1,
                                        showSubtitle: false, selected: false,
                                        style: EventRowStyle(
                                            dimmed: !thread.isEmpty && !member,
                                            spineColor: (!thread.isEmpty && idx >= spanMin && idx < spanMax) ? spine : nil,
                                            glow: member && thread.count > 1))
                                .contentShape(Rectangle())
                                .onHover { hoverID = $0 ? ev.id : (hoverID == ev.id ? nil : hoverID) }
                                .onTapGesture { open(selecting: ev.id, add: false) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { open(selecting: nil, add: false) } label: {
                    HStack(spacing: 4) {
                        Text("View all events").font(.caption.weight(.medium))
                        Image(systemName: "arrow.right").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(selecting id: String?, add: Bool) {
        let url = fileURL, folder = folderURL, name = context.name
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                EventLogExpandedView(fileURL: url, folderURL: folder, toolName: name,
                                     initialSelection: id, startAdding: add) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }
}

extension EventLogToolView {
    static let descriptor = ToolDescriptor(
        id: "event-log", title: "Event Log", defaultName: "Event Log",
        summary: "A visual, chronological log of decisions, iterations and abandoned branches — a light 'git' for the project.",
        icon: "clock",
        validSizes: [.small, .medium], files: ["event-log.md"],
        allowsMultiple: false,   // one project has one history — a single Event Log
        toolClass: .collector,
        makeView: { AnyView(EventLogToolView(context: $0)) }
    )
}

// MARK: - Timeline row (shared by the tile and the expanded list)

/// How a row participates in the selected event's lineage highlight.
struct EventRowStyle {
    var dimmed = false             // a thread is active and this row isn't part of it
    var spineColor: Color? = nil   // the gutter line below the dot is part of the active thread's spine
    var glow = false               // this row IS a thread member — the dot glows
    var parentLabel: String? = nil // "↳ parent title" shown at rest on branched events
}

private struct TimelineRow: View {
    let event: EventLog.Event
    let folderURL: URL?
    let isLast: Bool
    var showSubtitle: Bool = false
    var selected: Bool = false
    var style: EventRowStyle = EventRowStyle()

    private var thumbnail: Image? {
        guard let rel = event.images.first, let url = folderURL?.appendingPathComponent(rel) else { return nil }
        return nidusLoadImage(at: url)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Timeline gutter: coloured dot (glows for the active thread) + spine down to the next event.
            VStack(spacing: 0) {
                Circle().fill(event.type.color).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .background(Circle().fill(event.type.color.opacity(style.glow ? 0.35 : 0))
                        .frame(width: 18, height: 18).blur(radius: 3))
                Rectangle().fill(style.spineColor ?? Color.primary.opacity(0.15))
                    .frame(width: style.spineColor != nil ? 2.5 : 1.5)
                    .frame(maxHeight: .infinity)
                    .opacity(isLast ? 0 : 1)
            }
            .frame(width: 12)
            .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                // Type at a glance (icon + label in its colour) + the date — no need to memorise colours.
                HStack(spacing: 5) {
                    Image(systemName: event.type.icon).font(.system(size: 10, weight: .semibold))
                    Text(event.type.label).font(.caption2.weight(.semibold))
                    Text("·").font(.caption2).foregroundStyle(.tertiary)
                    Text(EventLog.dateLine(event.date)).font(.caption2).foregroundStyle(.secondary)
                }
                .foregroundStyle(event.type.color)
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.callout.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let parent = style.parentLabel {
                    Label(parent, systemImage: "arrow.turn.down.right")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                if showSubtitle, !event.notes.isEmpty {
                    Text(event.notes.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if let thumbnail {
                thumbnail.resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(.horizontal, selected ? 10 : 2).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(selected ? 0.06 : 0)))
        .opacity(style.dimmed ? 0.6 : 1)   // dimmed, but still readable
        .animation(.easeOut(duration: 0.18), value: style.dimmed)
    }
}

// MARK: - Expanded view (two-pane browser + editor)

struct EventLogExpandedView: View {
    @Environment(NidusModel.self) private var model
    let fileURL: URL?
    let folderURL: URL?
    let toolName: String
    let initialSelection: String?
    let startAdding: Bool
    let onClose: () -> Void

    @State private var selectedID: String?
    @State private var editing = false
    @State private var collapsed = false     // show only the selected event's branch
    @State private var timelineSearch = ""   // filters the left list by title or type
    @State private var draft = EventDraft()
    @State private var lastTapID: String?    // manual double-click detection (see handleTimelineTap)
    @State private var lastTapTime: Date = .distantPast

    init(fileURL: URL?, folderURL: URL?, toolName: String, initialSelection: String?,
         startAdding: Bool, onClose: @escaping () -> Void) {
        self.fileURL = fileURL; self.folderURL = folderURL; self.toolName = toolName
        self.initialSelection = initialSelection; self.startAdding = startAdding; self.onClose = onClose
    }

    private var events: [EventLog.Event] { _ = model.fileChangeTick; return EventLog.events(from: fileURL) }
    private var selected: EventLog.Event? { events.first { $0.id == selectedID } }

    var body: some View {
        HStack(spacing: 0) {
            leftPane.frame(width: 340)
            Divider().opacity(0.4)
            rightPane.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 900, height: 620)
        .glassCard()
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})
        .background(Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
        .onAppear {
            if startAdding { beginAdd() }
            else { selectedID = initialSelection ?? events.first?.id }
        }
    }

    // Left: the full timeline + add.
    private var leftPane: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock").font(.title3).foregroundStyle(.secondary)
                Text(toolName.isEmpty ? "Event Log" : toolName).font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
            Divider().opacity(0.4)

            ZStack(alignment: .bottomLeading) {
                TidyScroll {
                    let list = displayList
                    let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
                    let thread = selectedThread
                    let spine = (selectedID != nil && !editing) ? EventLog.rootColor(of: selectedID!, in: events) : .accentColor
                    let idxs = list.enumerated().filter { thread.contains($0.element.id) }.map(\.offset)
                    let spanMin = idxs.min() ?? 0, spanMax = idxs.max() ?? 0
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { idx, ev in
                            let member = thread.contains(ev.id)
                            TimelineRow(event: ev, folderURL: folderURL, isLast: idx == list.count - 1,
                                        showSubtitle: true, selected: ev.id == selectedID && !editing,
                                        style: EventRowStyle(
                                            dimmed: !collapsed && !thread.isEmpty && !member,
                                            spineColor: (!thread.isEmpty && idx >= spanMin && idx < spanMax) ? spine : nil,
                                            glow: member && thread.count > 1,
                                            parentLabel: ev.parent.flatMap { byID[$0]?.title }))
                                .contentShape(Rectangle())
                                // A single .onTapGesture(count: 1) fires immediately — no wait. We detect
                                // the "double-click" ourselves by timing consecutive taps on the SAME row,
                                // instead of stacking a native count:2 gesture (which forces SwiftUI to
                                // delay every single click while it waits to see if a second one follows).
                                .onTapGesture { handleTimelineTap(ev) }
                                .help("Double-click to branch from this event")
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
                // Always-present round "+" to add an event, bottom-left, with a search field beside it.
                HStack(spacing: 8) {
                    EventCircleButton(icon: "plus", help: "Add event", action: beginAdd)
                    timelineSearchField
                }
                .padding(.leading, 14).padding(.trailing, 14).padding(.bottom, 14)
            }

            // Collapse to just the selected branch — handy when the log gets long and a thread is
            // scattered across many entries.
            if !editing && (selectedThread.count > 1 || collapsed) {
                Divider().opacity(0.4)
                Button { withAnimation(.easeOut(duration: 0.2)) { collapsed.toggle() } } label: {
                    Label(collapsed ? "Show all events" : "Collapse related",
                          systemImage: collapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 11)
                }.buttonStyle(.plain)
            }
        }
    }

    private var selectedThread: Set<String> {
        guard let selectedID, !editing else { return [] }
        return EventLog.thread(of: selectedID, in: events)
    }
    private var displayList: [EventLog.Event] {
        let base = (collapsed && !selectedThread.isEmpty) ? events.filter { selectedThread.contains($0.id) } : events
        let q = timelineSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        // Match by title OR by type — typing "decision" surfaces every decision, still chronological.
        return base.filter { $0.title.lowercased().contains(q) || $0.type.label.lowercased().contains(q) }
    }

    /// Compact search field beside the "+" — filters the left list once a project has a lot of events.
    private var timelineSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Search events…", text: $timelineSearch)
                .textFieldStyle(.plain).font(.callout)
                #if os(iOS)
                .autocorrectionDisabled()
                #endif
            if !timelineSearch.isEmpty {
                Button { timelineSearch = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
        .frame(maxWidth: .infinity)
    }

    // Right: read the selected event, or edit/add. The pencil (edit) lives OUTSIDE the card, top-left
    // — mirroring the close "X" at top-right — so it's a stable corner control, not part of the card
    // content. Switching between read/edit cross-fades instead of cutting abruptly.
    @ViewBuilder private var rightPane: some View {
        Group {
            if editing {
                EventEditPane(draft: $draft, folderURL: folderURL, allEvents: events,
                              onSave: commit, onCancel: cancelEdit)
            } else if let ev = selected {
                EventReadPane(event: ev, folderURL: folderURL, parentTitle: parentTitle(of: ev),
                              onOpenParent: { if let p = ev.parent { withAnimation(.easeInOut(duration: 0.18)) { editing = false; selectedID = p } } },
                              onDelete: { delete(ev) })
            } else {
                Text("Select an event, or add one.").font(.callout).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: editing)
        .animation(.easeInOut(duration: 0.18), value: selectedID)
        .overlay(alignment: .topTrailing) { HoverCircleX(action: onClose).padding(14) }
        .overlay(alignment: .topLeading) {
            if !editing, let ev = selected {
                VStack(spacing: 10) {
                    EventCircleButton(icon: "pencil", size: 44, help: "Edit event", action: { beginEdit(ev) })
                    EventCircleButton(icon: "arrow.turn.down.right", size: 44,
                                      help: "Branch from this event", action: { beginBranch(ev) })
                }
                .padding(14)
            }
        }
    }

    private func parentTitle(of ev: EventLog.Event) -> String? {
        ev.parent.flatMap { p in events.first { $0.id == p }?.title }
    }

    // MARK: Actions

    private func beginAdd() {
        draft = EventDraft()
        collapsed = false
        editing = true
    }
    private func beginEdit(_ ev: EventLog.Event) {
        collapsed = false
        draft = EventDraft(id: ev.id, title: ev.title, notes: ev.notes, date: ev.date,
                           type: ev.type, images: ev.images, parent: ev.parent)
        editing = true
    }
    /// Fast path: a brand-new event, already linked as branching from the one you're viewing.
    private func beginBranch(_ ev: EventLog.Event) {
        collapsed = false
        draft = EventDraft(parent: ev.id)
        editing = true
    }

    /// Selection always happens INSTANTLY on the first tap (no native double-tap delay). A second tap
    /// on the same row within the system double-click window is treated as a manual "double-click" and
    /// triggers the branch shortcut on top of the (already-applied) selection.
    private func handleTimelineTap(_ ev: EventLog.Event) {
        let now = Date()
        let isDoubleClick = lastTapID == ev.id && now.timeIntervalSince(lastTapTime) < 0.4
        editing = false
        selectedID = ev.id
        if isDoubleClick {
            lastTapID = nil
            beginBranch(ev)
        } else {
            lastTapID = ev.id
            lastTapTime = now
        }
    }
    private func cancelEdit() { editing = false }

    private func commit() {
        guard let fileURL else { editing = false; return }
        let card = EventLog.makeCard(id: draft.id, title: draft.title, notes: draft.notes,
                                     date: draft.date, type: draft.type, images: draft.images,
                                     parent: draft.parent)
        if draft.id == nil { CardStore.append(card, to: fileURL) } else { CardStore.update(card, in: fileURL) }
        model.notifyFileChange()
        editing = false
        selectedID = card.id
    }

    private func delete(_ ev: EventLog.Event) {
        if let folderURL { for rel in ev.images { model.deleteCardImage(rel, inProjectFolder: folderURL) } }
        if let fileURL { CardStore.remove(id: ev.id, from: fileURL); model.notifyFileChange() }
        selectedID = events.first { $0.id != ev.id }?.id
    }
}

/// Editable draft of an event.
struct EventDraft {
    var id: String? = nil
    var title: String = ""
    var notes: String = ""
    var date: Date = Date()
    var type: EventType = .decision
    var images: [String] = []
    var parent: String? = nil
}

// MARK: - Read pane

private struct EventReadPane: View {
    let event: EventLog.Event
    let folderURL: URL?
    var parentTitle: String? = nil
    var onOpenParent: () -> Void = {}
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A compact card, centred in the available space (not stretched top-left with dead space
            // around it) — but still scrolls if the content is taller than the panel.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 20)
                        card
                        Spacer(minLength: 20)
                    }
                    .frame(minHeight: geo.size.height)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
            }

            Divider().opacity(0.4)
            HStack {
                Spacer()
                EventPill(title: "Delete", icon: "trash", action: onDelete)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    /// A FIXED size for every card — sized for the "reference" busiest event (title, a branch pill,
    /// 3 lines of notes, 3 photos) so switching between events never jumps in size. Shorter content
    /// just leaves breathing room inside; content taller than this scrolls internally.
    private static let cardSize = CGSize(width: 420, height: 460)

    private var card: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label(event.type.label, systemImage: event.type.icon)
                        .font(.caption.weight(.semibold)).foregroundStyle(event.type.color)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(event.type.color.opacity(0.14)))
                    Spacer(minLength: 8)
                    Text(EventLog.dateLine(event.date)).font(.caption).foregroundStyle(.secondary)
                }
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let parentTitle {
                    Button(action: onOpenParent) {
                        Label("Branches from: \(parentTitle)", systemImage: "arrow.turn.down.right")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }.buttonStyle(.plain)
                }
                if !event.notes.isEmpty {
                    Divider().opacity(0.3)
                    MarkdownView(blocks: MarkdownParser.parse(event.notes))
                }
                if !event.images.isEmpty {
                    Divider().opacity(0.3)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 8)], spacing: 8) {
                        ForEach(Array(event.images.enumerated()), id: \.offset) { _, rel in
                            if let url = folderURL?.appendingPathComponent(rel), let img = nidusLoadImage(at: url) {
                                img.resizable().aspectRatio(contentMode: .fill).frame(height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

// MARK: - Edit / add pane

private struct EventEditPane: View {
    @Environment(NidusModel.self) private var model
    @Binding var draft: EventDraft
    let folderURL: URL?
    let allEvents: [EventLog.Event]
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var importing = false
    @State private var showParentPicker = false
    @State private var parentSearch = ""
    @State private var addHover = false
    @State private var addTargeted = false
    @State private var showCalendar = false
    @FocusState private var addFocused: Bool

    /// Events that could be a parent: not self, not a descendant (no cycles), and allowed by the one
    /// linking rule (an Abandoned can only branch from a Decision or an Iteration).
    private var parentOptions: [EventLog.Event] {
        let invalid = EventLog.invalidParents(for: draft.id, in: allEvents)
        return allEvents.filter { !invalid.contains($0.id) && EventType.canParent(child: draft.type, parent: $0.type) }
    }
    private var filteredParents: [EventLog.Event] {
        let q = parentSearch.trimmingCharacters(in: .whitespaces).lowercased()
        // Match by title OR by type — so typing "decision" surfaces every decision, chronologically.
        return q.isEmpty ? parentOptions
            : parentOptions.filter { $0.title.lowercased().contains(q) || $0.type.label.lowercased().contains(q) }
    }
    private var parentName: String {
        draft.parent.flatMap { p in allEvents.first { $0.id == p }?.title } ?? "None (a root event)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Type chips.
                    sectionLabel("Type")
                    HStack(spacing: 7) {
                        ForEach(EventType.allCases) { t in typeChip(t) }
                    }
                    // Parent — the event this one iterates / is a milestone of (optional). Searchable.
                    if !allEvents.filter({ $0.id != draft.id }).isEmpty {
                        sectionLabel("Branches from")
                        Button { parentSearch = ""; showParentPicker = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(.secondary)
                                Text(parentName).font(.callout).foregroundStyle(draft.parent == nil ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 8).background(fieldBg())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showParentPicker, arrowEdge: .bottom) { parentPickerPopover }
                    }
                    // Title.
                    sectionLabel("Title")
                    TextField("What happened?", text: $draft.title)
                        .textFieldStyle(.plain).font(.title3.weight(.semibold))
                        .padding(.horizontal, 11).padding(.vertical, 8).background(fieldBg())
                    // Notes.
                    sectionLabel("Notes")
                    TextEditor(text: $draft.notes)
                        .font(.callout).scrollContentBackground(.hidden).scrollIndicators(.never)
                        .frame(height: 52).padding(.horizontal, 9).padding(.vertical, 6).background(fieldBg())
                    // References (images).
                    sectionLabel("References")
                    imagesStrip
                    // When (last — matters least: mostly for mapping an old decision log or planning
                    // future milestones/iterations; defaults to Today).
                    sectionLabel("When did / will this become relevant?")
                    Button { showCalendar = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar").font(.caption).foregroundStyle(.secondary)
                            Text(Calendar.current.isDateInToday(draft.date)
                                 ? "Today"
                                 : draft.date.formatted(.dateTime.month(.wide).day().year()))
                                .font(.callout)
                            Spacer()
                            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 8).background(fieldBg())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showCalendar, arrowEdge: .bottom) { EventDatePicker(date: $draft.date) }
                }
                .padding(22)
            }
            .scrollIndicators(.never)

            Divider().opacity(0.4)
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(action: onSave) { Text(draft.id == nil ? "Add event" : "Save").font(.callout.weight(.semibold)) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, let folderURL else { return }
            for url in urls { if let rel = model.importCardImage(from: url, intoProjectFolder: folderURL) { draft.images.append(rel) } }
        }
        // Changing the type can invalidate the chosen parent (e.g. → Abandoned can't hang off a Milestone).
        .onChange(of: draft.type) {
            if let p = draft.parent, let pe = allEvents.first(where: { $0.id == p }),
               !EventType.canParent(child: draft.type, parent: pe.type) { draft.parent = nil }
        }
    }

    private var parentPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                TextField("Search events…", text: $parentSearch).textFieldStyle(.plain).font(.callout)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    #endif
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pickerRow(icon: "circle.slash", tint: .secondary, title: "None (a root event)", subtitle: nil,
                              selected: draft.parent == nil) { draft.parent = nil; showParentPicker = false }
                    ForEach(filteredParents) { ev in
                        pickerRow(icon: ev.type.icon, tint: ev.type.color,
                                  title: ev.title.isEmpty ? "Untitled" : ev.title,
                                  subtitle: EventLog.dateLine(ev.date), selected: draft.parent == ev.id) {
                            draft.parent = ev.id; showParentPicker = false
                        }
                    }
                    if filteredParents.isEmpty && !parentSearch.isEmpty {
                        Text("No matches.").font(.caption).foregroundStyle(.tertiary)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                }
            }
            .frame(maxHeight: 240).scrollIndicators(.never)
        }
        .frame(width: 300)
    }

    private func pickerRow(icon: String, tint: Color, title: String, subtitle: String?, selected: Bool,
                           _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.caption).foregroundStyle(tint).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 6)
                if selected { Image(systemName: "checkmark").font(.caption).foregroundStyle(Color.accentColor) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func typeChip(_ t: EventType) -> some View {
        let on = draft.type == t
        return Button { draft.type = t } label: {
            HStack(spacing: 5) {
                Circle().fill(t.color).frame(width: 8, height: 8)
                Text(t.label).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(t.color.opacity(on ? 0.18 : 0.06)))
            .overlay(Capsule().strokeBorder(t.color.opacity(on ? 0.6 : 0), lineWidth: 1))
            .foregroundStyle(on ? .primary : .secondary)
        }.buttonStyle(.plain)
    }

    private var imagesStrip: some View {
        HStack(spacing: 10) {
            ForEach(Array(draft.images.enumerated()), id: \.offset) { idx, rel in
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let url = folderURL?.appendingPathComponent(rel), let img = nidusLoadImage(at: url) {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else { Color.primary.opacity(0.06) }
                    }
                    .frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button {
                        let rel = draft.images.remove(at: idx)
                        if let folderURL { model.deleteCardImage(rel, inProjectFolder: folderURL) }
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.body).foregroundStyle(.white, .black.opacity(0.5))
                    }.buttonStyle(.plain).padding(3)
                }
            }
            // "+" — click to pick, DROP an image on it, or hover + ⌘V to paste one (used all day).
            Button { importing = true } label: {
                Image(systemName: "plus").font(.title3).foregroundStyle(.secondary)
                    .scaleEffect(addHover || addTargeted ? 1.15 : 1)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(addHover || addTargeted ? 0.06 : 0)))
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(addTargeted ? Color.accentColor : Color.primary.opacity(addHover ? 0.4 : 0.25),
                                      style: StrokeStyle(lineWidth: addTargeted ? 2 : 1.5, dash: [5, 5])))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) // whole box is hoverable
            }
            .buttonStyle(.plain)
            .focusable().focusEffectDisabled().focused($addFocused)
            .onHover { addHover = $0; addFocused = $0 }
            .dropDestination(for: URL.self) { urls, _ in importImages(urls); return true } isTargeted: { addTargeted = $0 }
            .onImagePasteHere { pasteImage() }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: addHover || addTargeted)
        }
    }

    private func importImages(_ urls: [URL]) {
        guard let folderURL else { return }
        for url in urls { if let rel = model.importCardImage(from: url, intoProjectFolder: folderURL) { draft.images.append(rel) } }
    }
    private func pasteImage() {
        guard let folderURL else { return }
        let urls = ReferenceStore.clipboardImageURLs()
        if !urls.isEmpty { importImages(urls) }
        else if let png = ReferenceStore.clipboardImagePNG(),
                let rel = model.saveCardImage(png, ext: "png", intoProjectFolder: folderURL) { draft.images.append(rel) }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
    }
    private func fieldBg() -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
    }
}

/// A round, hover-reactive icon button (the "+" add and the pencil edit). Easy to hit, consistent.
private struct EventCircleButton: View {
    let icon: String
    var size: CGFloat = 42
    var help: LocalizedStringKey = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(hover ? 0.7 : 0.4), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.16), radius: hover ? 10 : 6, y: 3)
                .scaleEffect(hover ? 1.08 : 1)
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .animation(.easeOut(duration: 0.16), value: hover).help(help)
    }
}

/// The app's own month calendar for picking an event's day — same visual language as the deadline
/// calendar, but a plain single-day pick (no scopes). The time-of-day is preserved from `date`.
private struct EventDatePicker: View {
    @Binding var date: Date
    @State private var month: Date
    private let cal = Calendar.current

    init(date: Binding<Date>) {
        _date = date
        let c = Calendar.current
        _month = State(initialValue: c.date(from: c.dateComponents([.year, .month], from: date.wrappedValue)) ?? date.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                arrow("chevron.left") { shift(-1) }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.callout.weight(.semibold))
                Spacer()
                arrow("chevron.right") { shift(1) }
            }
            grid
        }
        .padding(12).frame(width: 236)
    }

    private func arrow(_ system: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: system).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var grid: some View {
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = (cal.component(.weekday, from: month) + 5) % 7   // Monday-first
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 3), count: 7)
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { off, ch in
                Text(String(ch)).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).id("wd\(off)")
            }
            ForEach(0..<leading, id: \.self) { i in Color.clear.frame(height: 28).id("b\(i)") }
            ForEach(1...daysInMonth, id: \.self) { day in dayCell(day).id("d\(day)") }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let d = cal.date(byAdding: .day, value: day - 1, to: month) ?? month
        let selected = cal.isDate(d, inSameDayAs: date)
        let isToday = cal.isDateInToday(d)
        return Text("\(day)")
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(selected ? Color.white : (isToday ? .primary : .secondary))
            .background {
                if selected { Circle().fill(Color.accentColor).frame(width: 28, height: 28) }
                else if isToday { Circle().strokeBorder(Color.secondary.opacity(0.5)).frame(width: 28, height: 28) }
            }
            .contentShape(Rectangle())
            .onTapGesture { pick(d) }
    }

    /// Today keeps the real moment (a time). Any other day is stored at 00:00 — the hour isn't
    /// meaningful for a past/future day, so no time is shown.
    private func pick(_ day: Date) {
        date = cal.isDateInToday(day) ? Date() : cal.startOfDay(for: day)
    }
    private func shift(_ n: Int) {
        withAnimation(.easeOut(duration: 0.15)) { month = cal.date(byAdding: .month, value: n, to: month) ?? month }
    }
}

/// A soft, hover-reactive pill (e.g. "Delete") — same calm language as the other cards, no alarm red.
private struct EventPill: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.callout.weight(.medium)).foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.primary.opacity(hover ? 0.10 : 0)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(hover ? 0.22 : 0.14)))
        }
        .buttonStyle(.plain).onHover { hover = $0 }.animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Small circular close button used in the expanded panel corner.
private struct HoverCircleX: View {
    let action: () -> Void
    @State private var h = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30).background(Circle().fill(Color.primary.opacity(h ? 0.14 : 0.07)))
        }
        .buttonStyle(.plain).onHover { h = $0 }.animation(.easeOut(duration: 0.12), value: h)
    }
}
