//
//  GreetingPanelView.swift
//  Nidus
//
//  Layer 1 — the Greeting Panel. A minimal, focused, glassy entry point to your projects:
//  keyboard-first fuzzy search (by project AND discipline), a few recents, and New. NIDUS top-left
//  (aligned with the controls), a human salutation centred over "Ready when you are." (the name is
//  editable in place: double-click → type → Enter), a living search bar that pulses, an elegant
//  rule, and the recents. Arrow keys move the result selection; Enter opens it.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct GreetingPanelView: View {
    @Environment(NidusModel.self) private var model
    @Environment(\.openURL) private var openURL
    /// Opens a project in this window (Greeting → Workspace, same surface).
    let onOpen: (ProjectRef) -> Void

    @AppStorage("nidus.userName") private var savedName = ""
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var showingAdd = false
    @State private var editingName = false
    @State private var nameDraft = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var nameFocused: Bool

    private let githubURL = URL(string: "https://github.com/ParamoStudio/Nidus")!
    private let blue = Color(hex: "#3A5BFF")

    private var results: [ProjectHit] { model.searchProjects(query) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            if showingAdd {
                AddProjectView(
                    onCancel: { withAnimation(.easeInOut(duration: 0.4)) { showingAdd = false } },
                    onCreate: { ref in onOpen(ref) }
                )
                .transition(.blurReplace)
            } else {
                greetingSurface.transition(.blurReplace)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showingAdd)
    }

    private var greetingSurface: some View {
        VStack(spacing: 0) {
            topRow
            Spacer(minLength: 14)
            metaballHero
            VStack(alignment: .leading, spacing: 20) {
                greetingBlock
                searchField
                Group {
                    if isSearching {
                        resultsList
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            separator
                            recentsSection
                        }
                    }
                }
                .transition(.opacity)
            }
            Spacer(minLength: 16)
        }
        .padding(.top, 22)
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.28), value: isSearching)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    // MARK: - Top row: NIDUS (left) + controls (right)

    private var topRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("NIDUS")
                .font(.system(size: 13, weight: .semibold))
                .tracking(3)
                .foregroundStyle(.secondary)
            Spacer()
            AppearanceToggle()
            IconButton(systemName: "questionmark", help: "About Nidus (GitHub)") {
                openURL(githubURL)
            }
        }
    }

    // MARK: - Metaball hero (always at the top; shrinks away to give the search room)

    /// The living app "avatar" — the same metaball as the vault picker. It stays above the
    /// greeting; the moment you start searching it shrinks to nothing (a genuine size collapse,
    /// driven by the Canvas frame, not a fade) so results get the room, and grows back from the
    /// centre when the query clears — the same elegant centre-out feel as the welcome bloom.
    private var metaballHero: some View {
        MetaballView(seed: 42, avatar: true)
            .frame(width: heroSize, height: heroSize)
            .frame(maxWidth: .infinity)
            .padding(.bottom, isSearching ? 0 : 14)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: isSearching)
    }

    private var heroSize: CGFloat { isSearching ? 0 : 104 }

    // MARK: - Greeting (centred; editable name)

    private var greetingBlock: some View {
        VStack(spacing: 8) {
            salutationRow
            Text("Ready when you are.")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 2)
    }

    private var salutationRow: some View {
        HStack(spacing: 0) {
            Text("\(greetingWord), ")
            nameView
            Text(".")
        }
        .font(.system(size: 15))
        .underline()
        .foregroundStyle(.primary.opacity(0.7))
    }

    /// The name: a plain Text until you double-click it, then an inline field (no popup). The
    /// double-click clears it and drops a blinking cursor; Enter saves it for next time.
    @ViewBuilder
    private var nameView: some View {
        if editingName {
            TextField("", text: $nameDraft)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .fixedSize()
                .tint(.accentColor)
                .onSubmit(commitName)
                #if os(macOS)
                .onExitCommand { cancelName() }
                #endif
        } else {
            Text(displayName)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { beginEditingName() }
                .help("Double-click to rename")
        }
    }

    // MARK: - Search (living, pulsing glow; arrows move the selection)

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Jump to any project…", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($searchFocused)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit(openSelected)
                .onKeyPress(.upArrow) { moveSelection(-1) }
                .onKeyPress(.downArrow) { moveSelection(1) }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        // The glow pulses via TimelineView (time-driven) instead of a repeatForever animation —
        // the latter runs away when this view is removed by the morph transition.
        .background {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let p = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.8)
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: blue.opacity(glowOpacity(p)), radius: glowRadius(p))
            }
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        .animation(.easeInOut(duration: 0.35), value: isSearching)
    }

    private var glowActive: Bool { searchFocused || isSearching }
    private func glowOpacity(_ p: Double) -> Double { (glowActive ? 0.5 : 0.28) * (0.55 + 0.45 * p) }
    private func glowRadius(_ p: Double) -> CGFloat { (glowActive ? 20 : 12) + CGFloat(p) * 8 }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 6) {
                if results.isEmpty {
                    Text("No projects match.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                } else {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                        ResultRow(hit: hit, selected: index == selectedIndex,
                                  folderURL: model.projectFolderURL(hit.ref),
                                  onHover: { selectedIndex = index },
                                  action: { open(hit.ref) })
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 240) // results scroll inside the fixed panel (no window resize)
    }

    // MARK: - Separator + recents

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.14))
            .frame(height: 1)
            .shadow(color: .white.opacity(0.3), radius: 3)
            .padding(.top, 2)
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Recent projects")
            HStack(spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.4)) { showingAdd = true } } label: {
                    SphereView(label: String(localized: "New"), icon: "plus", style: .add, diameter: 52)
                }
                .buttonStyle(.plain)
                ForEach(model.openingProjects) { hit in
                    Button { open(hit.ref) } label: {
                        SphereView(label: hit.project.name,
                                   icon: hit.project.icon ?? Project.defaultIcon,
                                   style: .neutral, diameter: 52,
                                   folderURL: model.projectFolderURL(hit.ref), monochrome: true,
                                   pinned: model.isPinned(hit.ref))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity) // centre the circles row in the panel
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(.secondary)
    }

    private var greetingWord: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return String(localized: "Good morning")
        case 12..<19: return String(localized: "Good afternoon")
        default: return String(localized: "Good evening")
        }
    }

    /// The shown name: the saved override, else the system user's first name.
    private var displayName: String {
        if !savedName.isEmpty { return savedName }
        #if os(macOS)
        let full = NSFullUserName()
        return full.split(separator: " ").first.map(String.init) ?? full
        #else
        return String(localized: "there")
        #endif
    }

    private func beginEditingName() {
        nameDraft = ""        // double-click clears it; the cursor waits
        searchFocused = false
        editingName = true
        // Focus on the next runloop — the field doesn't exist yet this cycle.
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { savedName = trimmed }
        editingName = false
        searchFocused = true
    }

    private func cancelName() {
        editingName = false
        searchFocused = true
    }

    private func moveSelection(_ delta: Int) -> KeyPress.Result {
        guard isSearching, !results.isEmpty else { return .ignored }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
        return .handled
    }

    private func openSelected() {
        guard isSearching, results.indices.contains(selectedIndex) else { return }
        open(results[selectedIndex].ref)
    }

    private func open(_ ref: ProjectRef) {
        model.markOpened(ref)
        onOpen(ref)
    }
}

/// A search result. Selection (keyboard or hover) shows a barely-there translucent fill plus a
/// soft accent glow in a capsule — matching the search bar — a gentle, sticky "you're here".
private struct ResultRow: View {
    let hit: ProjectHit
    let selected: Bool
    let folderURL: URL?
    let onHover: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProjectGlyph(icon: hit.project.icon, size: 24,
                             folderURL: folderURL, monochrome: true, circled: false)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.project.name)
                    Text(hit.discipline.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(.white.opacity(selected ? 0.09 : 0)))
            .shadow(color: .accentColor.opacity(selected ? 0.35 : 0), radius: 9)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selected)
        .onHover { if $0 { onHover() } }
    }
}
