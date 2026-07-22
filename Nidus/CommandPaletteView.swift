//
//  CommandPaletteView.swift
//  Nidus
//
//  Content search within the project (F) or across all projects (⌘F) — Blueprint §4.2/§4.3.
//  Distinct from the Greeting Panel's project search. Navigable by arrows or hover; Enter (or
//  click) reveals the match in the workspace with a momentary accent.
//

import SwiftUI

enum SearchScope { case project, all }

struct CommandPaletteView: View {
    @Environment(NidusModel.self) private var model
    let scope: SearchScope
    let currentRef: ProjectRef
    let onSelect: (ContentHit) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool

    private var results: [ContentHit] {
        model.searchContent(query, scope: scope, current: currentRef)
    }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(scope == .project ? "Search this project…" : "Search all projects…",
                          text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(openSelected)
                    .onChange(of: query) { _, _ in selectedIndex = 0 }
            }
            .padding(16)

            if isSearching {
                Divider()
                resultsArea
            }
        }
        .frame(width: 560)
        .glassCard()
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if results.isEmpty {
            Text("No matches.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                        Button { onSelect(hit); onClose() } label: { row(hit, selected: index == selectedIndex) }
                            .buttonStyle(.plain)
                            .onHover { if $0 { selectedIndex = index } }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 320)
        }
    }

    private func row(_ hit: ContentHit, selected: Bool) -> some View {
        let desc = ToolRegistry.descriptor(for: hit.toolID)
        return HStack(spacing: 10) {
            Image(systemName: desc.icon).foregroundStyle(.secondary).frame(width: 20)
            Text(hit.line).lineLimit(1)
            Spacer()
            Text(scope == .all ? hit.projectName : desc.defaultName)
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.18) : .clear))
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    private func openSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onSelect(results[selectedIndex])
        onClose()
    }
}
