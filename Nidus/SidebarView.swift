//
//  SidebarView.swift
//  Nidus
//
//  Hidden navigation sidebar (GUI workspace §9). Overlay, never pushes the content. Shows only
//  project NAMES — never data (preserves isolation). Top: NIDUS + a search field (project OR discipline
//  name, across every status, with a status dot). The working list shows only ACTIVE projects, grouped
//  by discipline, with up to 3 PINNED projects hoisted above. A bottom bar opens a persistent ARCHIVE
//  view (completed / archived / deprecated) that replaces the list until you go back to active.
//

import SwiftUI

struct SidebarView: View {
    @Environment(NidusModel.self) private var model
    let currentRef: ProjectRef
    let onSelect: (ProjectRef) -> Void
    var onHelp: () -> Void = {}
    /// Opens the phone pairing panel (pairing belongs to the vault, not to a project).
    var onPhone: () -> Void = {}

    @State private var query = ""
    @State private var archiveMode = false

    // MARK: Derived lists

    private var allDisciplines: [Discipline] { model.config?.disciplines ?? [] }

    /// Disciplines paired with the subset of their projects matching a status predicate (empties dropped).
    private func sections(_ include: (Project) -> Bool) -> [(discipline: Discipline, projects: [Project])] {
        allDisciplines.compactMap { d in
            let ps = d.projects.filter(include)
            return ps.isEmpty ? nil : (d, ps)
        }
    }

    private var pinnedIDs: Set<String> { Set(model.config?.pinnedProjects ?? []) }
    private var pinned: [ProjectHit] { model.pinnedHits }
    /// Active projects, excluding pinned ones (those are hoisted to the top section).
    private var activeSections: [(discipline: Discipline, projects: [Project])] {
        sections { ProjectStatus($0.status) == .active && !pinnedIDs.contains($0.id) }
    }
    private var archiveSections: [(discipline: Discipline, projects: [Project])] {
        sections { ProjectStatus($0.status) != .active }
    }
    private var hasArchive: Bool { !archiveSections.isEmpty }

    private var searchResults: [ProjectHit] {
        model.searchProjects(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NIDUS")
                .font(.custom("HelveticaNeue-Medium", size: 11)).tracking(3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

            SidebarSearchField(query: $query)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                searchList
            } else if archiveMode {
                archiveList
            } else {
                activeList
            }

            Spacer(minLength: 0)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .nidusGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Lists

    private var activeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !pinned.isEmpty {
                    pinnedSection
                    glowDivider
                }
                ForEach(Array(activeSections.enumerated()), id: \.element.discipline.id) { index, section in
                    disciplineSection(section.discipline, section.projects, showDots: false)
                    if index < activeSections.count - 1 { glowDivider }
                }
            }
            .padding(.top, 22).padding(.bottom, 4)
        }
    }

    private var archiveList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ARCHIVE")
                    .font(.custom("HelveticaNeue-Thin", size: 12)).tracking(1.5)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                if archiveSections.isEmpty {
                    Text("Nothing archived yet.").font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(archiveSections.enumerated()), id: \.element.discipline.id) { index, section in
                    disciplineSection(section.discipline, section.projects, showDots: true)
                    if index < archiveSections.count - 1 { glowDivider }
                }
            }
            .padding(.top, 18).padding(.bottom, 4)
        }
    }

    private var searchList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                if searchResults.isEmpty {
                    Text("No projects match.").font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity).padding(.top, 12)
                }
                ForEach(searchResults) { hit in
                    ProjectRow(name: hit.project.name,
                               subtitle: hit.discipline.name,
                               active: hit.ref == currentRef,
                               statusDot: ProjectStatus(hit.project.status).color,
                               pinned: pinnedIDs.contains(hit.project.id),
                               canPin: model.pinnedCount < NidusConfig.maxPinned,
                               onSelect: { onSelect(hit.ref) },
                               onTogglePin: { model.togglePin(hit.ref) })
                }
            }
            .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
        }
    }

    // MARK: Sections

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PINNED")
                .font(.custom("HelveticaNeue-Thin", size: 12)).tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.bottom, 3)
            VStack(spacing: 7) {
                ForEach(pinned) { hit in
                    ProjectRow(name: hit.project.name, subtitle: nil,
                               active: hit.ref == currentRef, statusDot: nil,
                               pinned: true, canPin: true,
                               onSelect: { onSelect(hit.ref) },
                               onTogglePin: { model.togglePin(hit.ref) })
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func disciplineSection(_ discipline: Discipline, _ projects: [Project], showDots: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(discipline.name)
                .font(.custom("HelveticaNeue-Thin", size: 14)).textCase(.uppercase).tracking(1.0)
                .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 14).padding(.bottom, 3)
            VStack(spacing: 7) {
                ForEach(projects) { project in
                    let ref = ProjectRef(disciplineID: discipline.id, projectID: project.id)
                    ProjectRow(name: project.name, subtitle: nil,
                               active: ref == currentRef,
                               statusDot: showDots ? ProjectStatus(project.status).color : nil,
                               pinned: pinnedIDs.contains(project.id),
                               canPin: model.pinnedCount < NidusConfig.maxPinned,
                               onSelect: { onSelect(ref) },
                               onTogglePin: { model.togglePin(ref) })
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var glowDivider: some View {
        Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
            .shadow(color: .white.opacity(0.3), radius: 3)
            .padding(.horizontal, 12).padding(.vertical, 2)
    }

    // MARK: Bottom bar (archive toggle + help)

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if archiveMode {
                sidebarToggle(icon: "chevron.up", label: "Back to active") {
                    withAnimation(.easeOut(duration: 0.2)) { archiveMode = false }
                }
            } else if hasArchive {
                sidebarToggle(icon: "archivebox", label: "Archive") {
                    withAnimation(.easeOut(duration: 0.2)) { archiveMode = true }
                }
            }
            HStack(spacing: 10) {
                Spacer()
                SidebarCircleButton(icon: "iphone.gen3", help: "Capture from your phone", action: onPhone)
                SidebarHelpButton(action: onHelp)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16).padding(.top, 6)
    }

    private func sidebarToggle(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.custom("HelveticaNeue", size: 11)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(.white.opacity(0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search field

private struct SidebarSearchField: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Search projects…", text: $query)
                .textFieldStyle(.plain).font(.custom("HelveticaNeue", size: 12))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(Capsule().fill(.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

// MARK: - Project row (select + hover-pin + optional status dot / discipline subtitle)

private struct ProjectRow: View {
    let name: String
    var subtitle: String? = nil
    let active: Bool
    var statusDot: Color? = nil
    var pinned: Bool = false
    var canPin: Bool = true
    let onSelect: () -> Void
    var onTogglePin: () -> Void = {}
    @State private var hovering = false

    private var squircleOpacity: Double {
        if active { return 0.07 }
        return hovering ? 0.09 : 0.05
    }
    /// The pin shows when the row is pinned (to unpin) or on hover (to pin, if allowed).
    private var showsPin: Bool { pinned || (hovering && canPin) }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Capsule().fill(active ? Color.accentColor : .clear).frame(width: 3, height: 18)
                    if let statusDot {
                        Circle().fill(statusDot).frame(width: 6, height: 6)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(.custom(active ? "HelveticaNeue-Medium" : "HelveticaNeue", size: 13))
                            .foregroundStyle(active || hovering ? .primary : .secondary)
                            .shadow(color: .white.opacity(hovering ? 0.5 : 0), radius: 6)
                            .shadow(color: .accentColor.opacity(hovering ? 0.45 : 0), radius: 11)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle).font(.custom("HelveticaNeue", size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9).padding(.horizontal, 12)
                .padding(.trailing, showsPin ? 22 : 0)   // room for the pin
                .background(Capsule().fill(LinearGradient(
                    colors: [.clear, .white.opacity(squircleOpacity)], startPoint: .leading, endPoint: .trailing)))
                .offset(x: hovering ? 5 : 0)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            if showsPin {
                Button { onTogglePin() } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(pinned ? Color.accentColor : .secondary)
                        .padding(6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .offset(x: hovering ? 5 : 0)
                .help(pinned ? "Unpin" : "Pin to top")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Help button

private struct SidebarHelpButton: View {
    let action: () -> Void
    var body: some View {
        SidebarCircleButton(icon: "questionmark", help: "How Nidus works", action: action)
    }
}

/// The sidebar's small round glass buttons (help, phone) — same reactive feel as the rest of the app.
private struct SidebarCircleButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 34, height: 34).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .nidusGlass(Circle(), interactive: true)
        .scaleEffect(hovering ? 1.1 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}
