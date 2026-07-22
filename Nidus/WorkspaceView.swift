//
//  WorkspaceView.swift
//  Nidus
//
//  Layer 2 — Workspace View (GUI workspace §3). Identity (top-left), ambient overview +
//  controls (top-right), the 5×2 grid (no scroll). Plus the auxiliary mechanisms (§4.2):
//  hidden sidebar (overlay), command palette (F / ⌘F), quick add (T / I), Customize Mode (⌘E).
//  Plain-letter shortcuts fire only when no text field is active (handled via the responder
//  chain: a focused field consumes the key first).
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A pending quick-capture: which style (idea/task) and the resolved `.md` of the target instance.
private struct QuickAddTarget: Identifiable {
    let id = UUID()
    let kind: QuickAddKind
    let fileURL: URL?
    let tool: String
    let name: String
}

struct WorkspaceView: View {
    @Environment(NidusModel.self) private var model
    @Environment(PhoneBridge.self) private var bridge
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    /// The tools marketplace (live, in active development) and the app's GitHub repo.
    private let toolsURL = URL(string: "https://paramostudio.github.io/nidus-tools/")!
    private let aboutURL = URL(string: "https://github.com/ParamoStudio/Nidus")!
    let ref: ProjectRef
    /// Returns to the Greeting Panel (same window/surface).
    let onBack: () -> Void
    /// Switches the window to another project (sidebar / cross-project search).
    let onOpen: (ProjectRef) -> Void

    @State private var isCustomizing = false
    @State private var editingProject = false
    @AppStorage("nidus.bridge.onboarded") private var phoneOnboarded = false
    @State private var showHelp = false
    @State private var addArea: GridArea?
    @State private var renamingSlot: ToolSlot?
    @State private var renameText = ""
    @State private var renameHotkey = ""
    @State private var lastValidHotkey = ""   // reverted-to letter when a typed one collides
    @State private var hotkeyError = false
    @State private var hotkeyErrorToken = 0   // so an old timer can't clear a freshly-shown error
    @State private var sidebarOpen = false
    @State private var showPalette = false
    @State private var paletteScope: SearchScope = .project
    @State private var quickAdd: QuickAddTarget?
    @State private var highlightedTool: String?
    @State private var overlay = WorkspaceOverlay()
    @State private var cardDrag = CardDragController()
    @State private var windowTooSmall = false
    @FocusState private var workspaceFocused: Bool

    private var hit: ProjectHit? { model.hit(for: ref) }

    var body: some View {
        ZStack {
            ZStack {
                workspaceContent
                sidebarRegion
                paletteOverlay
                quickAddOverlay
                detailOverlay
                libraryOverlay
                editorOverlay
                toolEditOverlay
                helpOverlay
                if let d = cardDrag.dragging {
                    CardFloatingView(card: d.card, folderURL: d.folderURL)
                        .position(d.location)
                        .allowsHitTesting(false)
                        // A soft spring so the lifted card trails the cursor (less "snappy").
                        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.82), value: d.location)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .coordinateSpace(.named("workspace"))
            .onPreferenceChange(ToolFramePreferenceKey.self) { cardDrag.frames = $0 }
            // Dragging inside a presented overlay must not leak to the workspace tools behind it.
            .onChange(of: overlay.content == nil) { _, isNil in cardDrag.overlayActive = !isNil }
            .blur(radius: windowTooSmall ? 18 : 0)
            .animation(.easeOut(duration: 0.2), value: windowTooSmall)

            if windowTooSmall { tooSmallNotice }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            // Nidus isn't a tiny app: below the functional size, blur and ask for more room.
            windowTooSmall = size.width < 1160 || size.height < 720
        }
        .environment(overlay)
        .environment(cardDrag)
        .focusable()
        .focusEffectDisabled()
        .focused($workspaceFocused)
        .onKeyPress { handleKey($0) }
        .onAppear { workspaceFocused = true }
    }

    @ViewBuilder
    private var libraryOverlay: some View {
        if let area = addArea {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { addArea = nil } }
                ToolLibraryPanel(projectRef: ref, area: area,
                                 onClose: { withAnimation(.easeOut(duration: 0.18)) { addArea = nil } })
            }
            .transition(.opacity)
        }
    }

    // MARK: - Content

    private var workspaceContent: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 18) {
                topZone
                WorkspaceGridView(
                    slots: hit?.project.layout?.grid ?? [],
                    projectRef: ref,
                    isEditing: isCustomizing,
                    highlightedTool: highlightedTool,
                    onAdd: { area in withAnimation(.easeOut(duration: 0.18)) { addArea = area } },
                    onRemove: {
                        Haptics.tap()
                        model.removeTool(ref, slotID: $0.id)
                    },
                    onRename: { slot in
                        let desc = ToolRegistry.descriptor(for: slot.tool)
                        renameText = slot.name ?? desc.defaultName
                        renameHotkey = slot.hotkey ?? desc.quickAction.map { String($0.defaultHotkey) } ?? ""
                        lastValidHotkey = renameHotkey
                        hotkeyError = false
                        renamingSlot = slot
                    },
                    onCommitGrid: { grid in model.setGrid(ref, grid) },
                    maxCellHeight: .infinity // fill the available height (use the bottom space too)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 24)
            .padding(.top, 44) // room for the Blueprint pill that floats just above the identity card
            .padding(.bottom, 22)
            .overlay(alignment: .bottomTrailing) { phoneOnboarding.padding(28) }
            .overlay(alignment: .bottom) { phoneToast.padding(.bottom, 26) }
        }
    }

    /// A quiet floating note while phone captures are being collected — a silent import reads as a
    /// glitch, but a routine empty check shouldn't announce itself either (PhoneBridge decides).
    @ViewBuilder private var phoneToast: some View {
        if let toast = bridge.toast {
            HStack(spacing: 8) {
                if bridge.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "iphone.gen3").font(.caption)
                }
                Text(toast).font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .glassCard(cornerRadius: 20)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.22), value: toast)
        }
    }

    /// A one-time nudge, right after the first project exists: you can capture into this from your phone.
    /// Dismissing (either way) never shows it again — the sidebar button is the permanent entry point.
    @ViewBuilder private var phoneOnboarding: some View {
        if !phoneOnboarded, model.allProjects.count == 1, !bridge.isConfigured {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "iphone.gen3").font(.callout).foregroundStyle(Color.accentColor)
                    Text("Capture from your phone").font(.callout.weight(.semibold))
                }
                Text("Jot ideas or tasks into this project while you're away, and Nidus files them when you're back.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Show me") { phoneOnboarded = true; openPhonePanel() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Not now") { phoneOnboarded = true }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 290, alignment: .leading)
            .padding(14)
            .glassCard()
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// Shown (over a blurred workspace) when the window is dragged below the functional size.
    private var tooSmallNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.left.and.arrow.up.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("Make the window bigger")
                .font(.title3.weight(.semibold))
            Text("Nidus works best at a larger size.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .glassCard()
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Top zone: identity (left) + controls & overview (right)

    private var topZone: some View {
        HStack(alignment: .top, spacing: 16) {
            IconButton(systemName: "chevron.left", help: "Back to Greeting") { onBack() }
            identityCard
            // Customize Mode reveals the project's lifecycle controls just to the right of its card.
            if isCustomizing {
                ProjectStatusControls(
                    ref: ref,
                    onForked: { forkRef in
                        model.markOpened(forkRef)
                        withAnimation(.easeOut(duration: 0.2)) { isCustomizing = false }
                        onOpen(forkRef)
                    },
                    onDeleted: {
                        withAnimation(.easeOut(duration: 0.2)) { isCustomizing = false }
                        onBack()
                    })
                .transition(.opacity)
            }
            Spacer(minLength: 16) // centred breathing room (horizontal only — must not grow height)
            overviewCard
            rightControls
        }
        .frame(height: 200) // pin the top band so the grid below is never squeezed
    }

    // MARK: Project identity (left, ~20% larger)

    private var identityCard: some View {
        let isLinked = hit?.project.linkedLocation != nil
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                projectIcon
                VStack(alignment: .leading, spacing: 5) {
                    Group {
                        Text(hit?.project.name ?? "Project")
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                        if let discipline = hit?.discipline.name {
                            Text(discipline).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    // The title's line only needs to clear the top-right control (Open Project Folder
                    // when linked, else nothing). The Blueprint pill now floats OUTSIDE the card.
                    .padding(.trailing, isLinked ? 160 : 44)
                    descriptionView   // full width — nothing overlaps it now
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            // Up to three user shortcuts, centred. In Customize Mode, three configurable slots.
            ProjectQuickActions(
                actions: hit?.project.quickActions ?? [],
                isEditing: isCustomizing,
                onRun: { runQuickAction($0) },
                onChange: { model.setQuickActions(ref, $0) },
                forkedOriginal: hit?.project.forkedFrom.map {
                    ProjectRef(disciplineID: $0.disciplineID, projectID: $0.projectID)
                },
                onOpenOriginal: { origin in
                    if model.hit(for: origin) != nil { model.markOpened(origin); onOpen(origin) }
                },
                forks: model.forks(of: ref),
                onOpenFork: { fork in model.markOpened(fork); onOpen(fork) }
            )
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 528, height: 190, alignment: .topLeading)
        .glassCard()
        // The edit pencil + Open Project Folder live in the top-right corner of the card.
        .overlay(alignment: .topTrailing) { cardTopControls.padding(20) }
    }

    private let blueprintLabel = "Project Blueprint"

    /// Opens the phone pairing / capture panel in the shared overlay.
    private func openPhonePanel() {
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                PhoneBridgePanel { withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() } }
            }
        }
    }

    /// The Blueprint pill floats just ABOVE the header, aligned to the right (over the calendar's corner),
    /// so it has presence without crowding anything. Not shown in Customize Mode.
    @ViewBuilder private var blueprintPillOverlay: some View {
        if !isCustomizing, let folder = model.projectFolderURL(ref) {
            BlueprintPill(hasContent: blueprint != nil, label: blueprintLabel) {
                withAnimation(.easeOut(duration: 0.2)) {
                    overlay.present {
                        BlueprintPanel(projectFolder: folder, vaultURL: model.vaultURL) {
                            withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                        }
                    }
                }
            }
            .offset(y: -34)   // lift it above the calendar's top edge
            .transition(.opacity.combined(with: .scale))
        }
    }

    /// Top-right of the card: the edit pencil (Customize Mode) + Open Project Folder.
    private var cardTopControls: some View {
        HStack(spacing: 8) {
            if isCustomizing {
                IconButton(systemName: "pencil", help: "Edit project") {
                    withAnimation(.easeOut(duration: 0.18)) { editingProject = true }
                }
                .transition(.opacity.combined(with: .scale))
            }
            if let linked = hit?.project.linkedLocation {
                openFolderControl(linked)
            }
        }
    }

    /// The pinned Blueprint, re-read whenever the project changes (so the pill reflects the right file).
    private var blueprint: Blueprint? {
        model.projectFolderURL(ref).flatMap { BlueprintStore.load(projectFolder: $0) }
    }

    // MARK: - Project editor + help (overlays)

    @ViewBuilder
    private var editorOverlay: some View {
        if editingProject {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { editingProject = false } }
                ZStack {
                    // Absorb taps inside the panel so a mis-click beside a field doesn't fall
                    // through to the dimmed backdrop and dismiss the editor (only the blurred area
                    // outside the panel dismisses).
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.clear)
                        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .onTapGesture { }
                    AddProjectView(
                        onCancel: { withAnimation(.easeOut(duration: 0.18)) { editingProject = false } },
                        onCreate: { newRef in
                            editingProject = false
                            if newRef != ref { onOpen(newRef) } // discipline change → re-point the window
                        },
                        editing: ref
                    )
                }
                .frame(width: 380, height: 600)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var helpOverlay: some View {
        if showHelp {
            ZStack {
                Color.black.opacity(0.28).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showHelp = false } }
                WorkspaceHelpCard { withAnimation(.easeInOut(duration: 0.2)) { showHelp = false } }
            }
            .transition(.opacity)
        }
    }

    /// Fits the description in the space available: a couple more lines when there are no quick
    /// actions below, fewer when the card's bottom row is occupied (avoids clipping the pills).
    private var descriptionLineLimit: Int {
        (hit?.project.quickActions?.isEmpty ?? true) ? 5 : 3
    }

    @ViewBuilder
    private var descriptionView: some View {
        if let description = hit?.project.description, !description.isEmpty {
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(descriptionLineLimit)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Placeholder until the project editor (Customize Mode) lets you write one.
            Text("Add a description…")
                .font(.callout)
                .italic()
                .foregroundStyle(.tertiary)
        }
    }

    /// The project icon held under a clean round glass "watch crystal" — no glare, just a soft
    /// perimeter glow and the icon contained within (the old sphere-with-glare is deprecated).
    private var projectIcon: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            ProjectGlyph(icon: hit?.project.icon, size: 72, folderURL: model.projectFolderURL(ref))
        }
        .frame(width: 72, height: 72)
        .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
        .shadow(color: .white.opacity(0.16), radius: 7)
    }

    @ViewBuilder
    private func openFolderControl(_ linked: LinkedLocation) -> some View {
        if linked.deviceId == model.device.id {
            Button { openFolder(linked) } label: {
                Label("Open Project Folder", systemImage: "folder").font(.callout.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        } else {
            Label("Lives on \(linked.deviceName)", systemImage: "externaldrive")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Anchored overview-tool slot (landscape) — holds the Deadline Calendar (passive)

    private var overviewCard: some View {
        HStack(spacing: 16) {
            miniMonth
            Divider().overlay(.white.opacity(0.12))
            deadlinesList
        }
        .padding(18)
        .frame(width: 440, height: 200, alignment: .topLeading)
        .glassCard()
        // The Project Blueprint pill floats above the calendar's top-right corner.
        .overlay(alignment: .topTrailing) { blueprintPillOverlay }
    }

    /// Deadlines aggregated from every task manager in this project (refreshes on file changes).
    private var deadlineEntries: [DeadlineEntry] {
        _ = model.fileChangeTick
        return model.deadlineEntries(folderURL: model.projectFolderURL(ref),
                                     grid: hit?.project.layout?.grid ?? [])
    }

    /// The "several / no tags" marker colour — near-white on dark, near-black on light (visible, not
    /// radioactive). A single tag keeps its own colour.
    private var neutralDot: Color { colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8) }
    private func dotColor(_ e: DeadlineEntry) -> Color {
        e.colorIndex.map { TagPalette.color($0) } ?? neutralDot
    }

    /// Mini month (current month): a coloured dot under days with a day-deadline; a single soft band
    /// across a whole week for a week-deadline; a dot next to the month name for a month-deadline.
    private var miniMonth: some View {
        let cal = Calendar.current
        let now = Date()
        let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let daysInMonth = cal.range(of: .day, in: .month, for: now)!.count
        let leading = (cal.component(.weekday, from: firstOfMonth) + 5) % 7 // Monday-first
        let today = cal.component(.day, from: now)
        let entries = deadlineEntries
        var cells: [Int?] = Array(repeating: nil, count: leading)
        cells.append(contentsOf: (1...daysInMonth).map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(firstOfMonth.formatted(.dateTime.month(.wide)))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let mc = monthDotColor(entries: entries, month: firstOfMonth) {
                    Circle().fill(mc).frame(width: 5, height: 5)
                }
            }
            HStack(spacing: 3) {
                ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { _, c in
                    Text(String(c)).font(.system(size: 7, weight: .medium)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                weekRow(row, rowIndex: r, firstOfMonth: firstOfMonth, leading: leading, today: today, entries: entries)
            }
        }
        .frame(width: 164)
    }

    /// One week (7 cells) with a single continuous soft band behind it when it has a week-deadline.
    private func weekRow(_ row: [Int?], rowIndex: Int, firstOfMonth: Date, leading: Int,
                         today: Int, entries: [DeadlineEntry]) -> some View {
        let cal = Calendar.current
        let monday = cal.date(byAdding: .day, value: rowIndex * 7 - leading, to: firstOfMonth) ?? firstOfMonth
        let weekEntries = entries.filter {
            $0.deadline.scope == .week &&
            cal.isDate(cal.startOfWeek(for: $0.deadline.date), inSameDayAs: cal.startOfWeek(for: monday))
        }
        let band: Color? = weekEntries.isEmpty ? nil : (weekEntries.count == 1 ? dotColor(weekEntries[0]) : neutralDot)
        return HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { col in
                dayCell(row[col], firstOfMonth: firstOfMonth, today: today, entries: entries)
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 1)
        .background {
            if let band { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(band.opacity(0.16)) }
        }
    }

    private func dayCell(_ day: Int?, firstOfMonth: Date, today: Int, entries: [DeadlineEntry]) -> some View {
        let cal = Calendar.current
        return Group {
            if let day {
                let d = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) ?? firstOfMonth
                let dayEntries = entries.filter { $0.deadline.scope == .day && cal.isDate($0.deadline.date, inSameDayAs: d) }
                let dot: Color? = dayEntries.isEmpty ? nil : (dayEntries.count == 1 ? dotColor(dayEntries[0]) : neutralDot)
                Text("\(day)")
                    .font(.system(size: 8))
                    .foregroundStyle(day == today ? .white : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 16)
                    .background { if day == today { Circle().fill(Color.accentColor).frame(width: 15, height: 15) } }
                    .overlay(alignment: .bottom) { if let dot { Circle().fill(dot).frame(width: 4, height: 4) } }
            } else {
                Color.clear.frame(maxWidth: .infinity, minHeight: 16)
            }
        }
    }

    /// A dot beside the month name if any task targets this whole month.
    private func monthDotColor(entries: [DeadlineEntry], month: Date) -> Color? {
        let cal = Calendar.current
        let monthEntries = entries.filter {
            $0.deadline.scope == .month && cal.isDate($0.deadline.date, equalTo: month, toGranularity: .month)
        }
        guard !monthEntries.isEmpty else { return nil }
        return monthEntries.count == 1 ? dotColor(monthEntries[0]) : neutralDot
    }

    /// Upcoming deadlines, nearest first, across every task manager.
    private var deadlinesList: some View {
        let upcoming = deadlineEntries.filter { $0.isRelevant() }.sorted { $0.sortDate < $1.sortDate }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Upcoming deadlines").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "calendar").font(.caption).foregroundStyle(.tertiary)
            }
            if upcoming.isEmpty {
                Spacer(minLength: 0)
                Text("No deadlines yet").font(.callout).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(upcoming.prefix(4)) { entry in deadlineRow(entry) }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deadlineRow(_ entry: DeadlineEntry) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor(entry)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.caption).lineLimit(1)
                Text("\(entry.deadline.pillText) · \(entry.listName)")
                    .font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Vertical control column (far right) + wordmark

    private var rightControls: some View {
        // The NIDUS wordmark lives in the window title bar (see WindowConfigurator), not here.
        VStack(spacing: 12) {
            AppearanceToggle()
            IconButton(systemName: isCustomizing ? "checkmark" : "square.grid.2x2",
                       active: isCustomizing, help: "Customize (⌘E)") {
                withAnimation(.easeOut(duration: 0.2)) { isCustomizing.toggle() }
            }
            .keyboardShortcut("e", modifiers: .command)
            IconButton(systemName: "wrench.and.screwdriver", help: "Browse the Nidus tools marketplace") {
                openURL(toolsURL)
            }
            IconButton(systemName: "arrow.triangle.branch", help: "Nidus on GitHub") {
                openURL(aboutURL)
            }
        }
    }

    // MARK: - Sidebar (overlay, slides over + fades in)

    /// One hot zone at the left edge. Hover in → opens; hover out → closes. The zone's hit width
    /// jumps to the panel width on open (so there's no slide-in race), while the panel slides in
    /// via offset inside the clip. Detection is immediate; the animation is smooth.
    private var sidebarRegion: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                SidebarView(currentRef: ref, onSelect: { selected in
                    sidebarOpen = false
                    if selected != ref { onOpen(selected) }
                }, onHelp: {
                    sidebarOpen = false
                    withAnimation(.easeInOut(duration: 0.2)) { showHelp = true }
                }, onPhone: {
                    sidebarOpen = false
                    openPhonePanel()
                })
                .frame(width: 168)
                .frame(maxHeight: .infinity)
                .offset(x: sidebarOpen ? 0 : -180)
                .opacity(sidebarOpen ? 1 : 0)
            }
            .frame(width: sidebarOpen ? 168 : 14)
            .frame(maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 4, height: 46)
                    .padding(.leading, 4)
                    .opacity(sidebarOpen ? 0 : 1)
            }
            .contentShape(Rectangle())
            .onHover { hovering in sidebarOpen = hovering }
            // Touch (iPad): hover never fires, so tapping the handle toggles the project changer open/shut.
            .onTapGesture { sidebarOpen.toggle() }
            Spacer()
        }
        .animation(.easeOut(duration: 0.4), value: sidebarOpen)
    }

    // MARK: - Command palette + quick add (overlays)

    @ViewBuilder
    private var paletteOverlay: some View {
        if showPalette {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                    .onTapGesture { closePalette() }
                CommandPaletteView(scope: paletteScope, currentRef: ref,
                                   onSelect: handleSearchSelect,
                                   onClose: closePalette)
                    .padding(.top, 40)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var quickAddOverlay: some View {
        if let target = quickAdd {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                    .onTapGesture { closeQuickAdd() }
                QuickAddView(kind: target.kind, fileURL: target.fileURL, tool: target.tool,
                             toolName: target.name, onClose: closeQuickAdd)
            }
            .transition(.opacity)
        }
    }

    /// Rename + quick-add hotkey editor for a tool instance (Customize Mode). A custom glass panel
    /// rather than a native alert, so the hotkey field can validate live and flash "already in use".
    @ViewBuilder
    private var toolEditOverlay: some View {
        if let slot = renamingSlot {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                    .onTapGesture { renamingSlot = nil }
                ToolEditPanel(
                    name: $renameText,
                    hotkey: $renameHotkey,
                    showsHotkey: ToolRegistry.descriptor(for: slot.tool).quickAction != nil,
                    hotkeyError: hotkeyError,
                    onHotkeyChange: { validateHotkey(for: slot) },
                    onSave: { commitToolEdit(slot) },
                    onCancel: { renamingSlot = nil })
            }
            .transition(.opacity)
        }
    }

    /// Keeps the hotkey field to a single letter and rejects one already claimed by another instance
    /// (its own default or override), flashing an error instead of silently shadowing the first tool.
    /// Careful: every write to `renameHotkey` re-fires this via .onChange, so we must NOT clear the
    /// error on the revert echo — only when a genuinely new, distinct letter is accepted.
    private func validateHotkey(for slot: ToolSlot) {
        var v = renameHotkey.lowercased()
        if v.count > 1 { v = String(v.suffix(1)) }   // single-letter field: keep the newest keystroke
        if v.isEmpty {
            if !renameHotkey.isEmpty { renameHotkey = "" }
            if !lastValidHotkey.isEmpty { lastValidHotkey = ""; hotkeyError = false }
            return
        }
        if hotkeyTaken(v, excluding: slot.id) {
            flashHotkeyError()
            if renameHotkey != lastValidHotkey { renameHotkey = lastValidHotkey } // reject the keystroke
            return
        }
        // Valid letter. Only touch the error/lastValid when it actually changed (not the echo).
        if v != lastValidHotkey { lastValidHotkey = v; hotkeyError = false }
        if renameHotkey != v { renameHotkey = v }
    }

    private func flashHotkeyError() {
        hotkeyError = true
        hotkeyErrorToken += 1
        let token = hotkeyErrorToken
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if hotkeyErrorToken == token { hotkeyError = false }
        }
    }

    /// Whether another instance on the board already resolves to `letter` (override, else its default).
    private func hotkeyTaken(_ letter: String, excluding slotID: String) -> Bool {
        guard let grid = hit?.project.layout?.grid else { return false }
        let l = letter.lowercased()
        return grid.contains { slot in
            guard slot.id != slotID,
                  let qa = ToolRegistry.descriptor(for: slot.tool).quickAction else { return false }
            return (slot.hotkey?.lowercased() ?? String(qa.defaultHotkey).lowercased()) == l
        }
    }

    private func commitToolEdit(_ slot: ToolSlot) {
        model.renameTool(ref, slotID: slot.id, to: renameText)
        if ToolRegistry.descriptor(for: slot.tool).quickAction != nil {
            model.setToolHotkey(ref, slotID: slot.id, to: renameHotkey)
        }
        renamingSlot = nil
    }

    /// Translucent detail panel (idea/task) over a dimmed, gaussian-blurred backdrop.
    @ViewBuilder
    private var detailOverlay: some View {
        if let content = overlay.content {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() } }
                content
            }
            .transition(.opacity)
        }
    }

    // MARK: - Keyboard handling (responder chain gates plain keys away from text fields)

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Any modal surface (editor, help, palette, quick-add) must swallow plain-letter shortcuts,
        // so typing in their fields never leaks into T/I/F workspace actions. Customize Mode too:
        // the tools are inert there and it hosts text fields (rename, quick-action config).
        guard !model.isEditingText, !showPalette, quickAdd == nil,
              !editingProject, !showHelp, !isCustomizing, !sidebarOpen, overlay.content == nil else { return .ignored }
        // Space opens whatever card the cursor is hovering — keyboard-friendly, and unambiguous
        // because only one card can be hovered at a time.
        if press.key == .space, press.modifiers.isEmpty, let hovered = cardDrag.hovered {
            openHoveredCard(hovered)
            return .handled
        }
        if press.key == "f" {
            if press.modifiers.contains(.command) { openPalette(.all); return .handled }
            if press.modifiers.isEmpty { openPalette(.project); return .handled }
            return .ignored
        }
        // Tool quick-add hotkeys are data-driven: each tool declares one in its descriptor, and an
        // instance can override the letter (so a duplicated "Recipes" can use R). First match wins.
        if press.modifiers.isEmpty, let slot = quickAddSlot(forKey: press.key.character) {
            // Notebook's hotkey opens its library straight into a new note, not the line-append sheet.
            if slot.tool == NotebookToolView.descriptor.id {
                openNotebookNewNote(slot: slot)
            } else if let tool = model.installedTools.first(where: { $0.id == slot.tool }) {
                openInstalledToolExpanded(tool, slot: slot)   // an installed tool's hotkey opens its expanded view
            } else {
                openQuickAdd(for: slot)
            }
            return .handled
        }
        return .ignored
    }

    /// An installed tool's declared hotkey opens its expanded view.
    private func openInstalledToolExpanded(_ tool: InstalledTool, slot: ToolSlot) {
        let folder = model.projectFolderURL(ref)
        let file = (slot.files?.first ?? tool.manifest.store.first).flatMap { folder?.appendingPathComponent($0) }
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                InstalledToolExpandedView(tool: tool, primaryFile: file, folderURL: folder,
                                          size: slot.toolSize.rawValue) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }

    /// Opens the Notebook library and drops straight into a fresh note (the "n" quick action).
    private func openNotebookNewNote(slot: ToolSlot) {
        let folder = model.projectFolderURL(ref)
        let name = slot.name ?? NotebookToolView.descriptor.defaultName
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                NotebookLibraryView(projectFolder: folder, toolName: name, startNewNote: true) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }

    /// The tool instance whose effective quick-add hotkey matches `key` (override else default).
    private func quickAddSlot(forKey key: Character) -> ToolSlot? {
        guard let grid = hit?.project.layout?.grid else { return nil }
        let pressed = String(key).lowercased()
        return grid.first { slot in
            let desc = ToolRegistry.descriptor(for: slot.tool)
            guard let qa = desc.quickAction else { return false }
            let effective = slot.hotkey?.lowercased() ?? String(qa.defaultHotkey).lowercased()
            return pressed == effective
        }
    }

    // MARK: - Actions

    /// Opens the hovered card's reusable detail popup at the workspace level (Space shortcut).
    private func openHoveredCard(_ h: CardDragController.HoverInfo) {
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                CardDetailView(card: h.card, fileURL: h.fileURL, folderURL: h.folderURL,
                               toolIcon: h.toolIcon, toolName: h.toolName) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }

    private func openPalette(_ scope: SearchScope) {
        paletteScope = scope
        withAnimation(.easeOut(duration: 0.18)) { showPalette = true }
    }

    private func closePalette() {
        withAnimation(.easeOut(duration: 0.18)) { showPalette = false }
        workspaceFocused = true
    }

    /// Opens the quick-capture for a specific tool instance, targeting its own `.md` file.
    private func openQuickAdd(for slot: ToolSlot) {
        let desc = ToolRegistry.descriptor(for: slot.tool)
        guard let qa = desc.quickAction else { return }
        let file = slot.files?.first ?? desc.files.first
        let url = file.flatMap { name in model.projectFolderURL(ref)?.appendingPathComponent(name) }
        withAnimation(.easeOut(duration: 0.18)) {
            quickAdd = QuickAddTarget(kind: qa.kind, fileURL: url, tool: slot.tool,
                                      name: slot.name ?? desc.defaultName)
        }
    }

    private func closeQuickAdd() {
        withAnimation(.easeOut(duration: 0.18)) { quickAdd = nil }
        workspaceFocused = true
    }


    /// A search hit: switch window if it's another project, then reveal the exact card in its tool
    /// instance (the tool scrolls to it and flashes it). The model is shared across windows.
    private func handleSearchSelect(_ hit: ContentHit) {
        if hit.ref != ref { onOpen(hit.ref) }
        model.reveal(ref: hit.ref, slotID: hit.slotID, cardID: hit.cardID)
    }

    private func openFolder(_ linked: LinkedLocation) {
        #if os(macOS)
        guard FileManager.default.fileExists(atPath: linked.path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: linked.path))
        #endif
    }

    /// Runs a card quick action: open a web URL (any platform), open an app/file/folder, or execute
    /// a script (macOS).
    private func runQuickAction(_ action: QuickAction) {
        switch action.kind {
        case .web:
            if let url = URL(string: action.target) { openURL(url) }
        case .app, .route:
            #if os(macOS)
            guard FileManager.default.fileExists(atPath: action.target) else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: action.target))
            #endif
        case .script:
            #if os(macOS)
            runScript(at: action.target)
            #endif
        }
    }

    #if os(macOS)
    /// Executes a user-chosen script: directly if it's executable (respecting its shebang), else via
    /// the login shell. Personal automation on the user's own machine (the path is picked in-app).
    private func runScript(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        do {
            try proc.run()
        } catch {
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
            shell.arguments = [path]
            try? shell.run()
        }
    }
    #endif
}

/// The tool-instance editor: rename + (for tools that expose quick-add) a validated one-letter
/// hotkey. Matches the app's glass language; the hotkey field flashes when a letter is taken.
private struct ToolEditPanel: View {
    @Binding var name: String
    @Binding var hotkey: String
    let showsHotkey: Bool
    let hotkeyError: Bool
    let onHotkeyChange: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit tool").font(.headline)

            fieldLabel("Name")
            TextField("Name", text: $name)
                .textFieldStyle(.plain).font(.title3)
                .focused($nameFocused)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(fieldBackground())
                .onChange(of: name) { if name.count > 20 { name = String(name.prefix(20)) } }

            if showsHotkey {
                // Label + small letter box on ONE line — keeps the panel compact.
                HStack(spacing: 12) {
                    fieldLabel("Quick-add hotkey")
                    if hotkeyError {
                        Text("· already in use")
                            .font(.caption2.weight(.medium)).foregroundStyle(.red)
                            .transition(.opacity)
                    }
                    Spacer()
                    TextField("A", text: $hotkey)
                        .textFieldStyle(.plain).font(.title3)
                        .multilineTextAlignment(.center)
                        .frame(width: 52)
                        .padding(.vertical, 7)
                        .background(fieldBackground(error: hotkeyError))
                        .onChange(of: hotkey) { onHotkeyChange() }
                        #if os(iOS)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        #endif
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 400)
        .glassCard()
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
        .animation(.easeOut(duration: 0.15), value: hotkeyError)
        .onAppear { nameFocused = true }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
    }

    private func fieldBackground(error: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(error ? Color.red.opacity(0.6) : Color.primary.opacity(0.12)))
    }
}
