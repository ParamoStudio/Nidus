//
//  ToolLibrarySheet.swift
//  Nidus
//
//  Customize Mode — the tool library (GUI workspace §8). A small Liquid Glass panel.
//  TEMPLATE TOOLS (top): the registered tool types — adding one creates a fresh instance.
//  PROJECT TOOLS (below): instances that were used and removed (their `.md` persists) — adding
//  one re-attaches it (no duplicate). Templates show the tool TYPE name; project tools show the
//  instance's own name. All display info is read from descriptors / the instances — never hardcoded.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

struct ToolLibraryPanel: View {
    @Environment(NidusModel.self) private var model
    let projectRef: ProjectRef
    let area: GridArea
    let onClose: () -> Void

    @State private var abandonTarget: ToolSlot?
    @State private var uninstallTarget: InstalledTool?
    #if !os(macOS)
    @State private var importingTool = false
    #endif

    private var layout: ProjectLayout? { model.hit(for: projectRef)?.project.layout }
    private var placed: [ToolSlot] { layout?.grid ?? [] }
    private var detached: [ToolSlot] { layout?.detached ?? [] }

    /// Tool types that can be added fresh (singletons hidden if an instance already exists).
    private var templates: [ToolDescriptor] {
        ToolRegistry.all.filter { desc in
            desc.allowsMultiple
                || !(placed + detached).contains(where: { $0.tool == desc.id })
        }
    }
    private var builtInTemplates: [ToolDescriptor] {
        templates.filter { d in ToolRegistry.builtIn.contains { $0.id == d.id } }
    }
    private var installedTemplates: [ToolDescriptor] {
        templates.filter { d in model.installedTools.contains { $0.id == d.id } }
    }
    private func installedTool(_ id: String) -> InstalledTool? { model.installedTools.first { $0.id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add a tool").font(.title3.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Template tools") {
                        ForEach(builtInTemplates) { tool in
                            Button { addTemplate(tool) } label: {
                                card(icon: tool.icon, name: tool.defaultName,
                                     summary: tool.summary, sizes: tool.sizesInOrder)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider().opacity(0.5)
                    section("Installed tools") {
                        ForEach(installedTemplates) { tool in
                            Button { addTemplate(tool) } label: {
                                card(icon: tool.icon, name: tool.defaultName,
                                     summary: tool.summary, sizes: tool.sizesInOrder, showAdd: false)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) {
                                if let inst = installedTool(tool.id) {
                                    Button(role: .destructive) { uninstallTarget = inst } label: {
                                        Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                                            .padding(6).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).padding(6)
                                    .help("Uninstall this tool (its .js is removed; project data is kept)")
                                }
                            }
                        }
                        Button(action: importTool) {
                            Label("Import tool (.js)", systemImage: "square.and.arrow.down")
                                .font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: NidusRadius.inner))
                                .overlay(RoundedRectangle(cornerRadius: NidusRadius.inner)
                                    .strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        }
                        .buttonStyle(.plain)
                    }

                    if !detached.isEmpty {
                        Divider().opacity(0.5)
                        section("Project tools") {
                            ForEach(detached) { slot in
                                let desc = ToolRegistry.descriptor(for: slot.tool)
                                Button { attach(slot) } label: {
                                    card(icon: desc.icon,
                                         name: slot.name ?? desc.defaultName,
                                         summary: desc.summary, sizes: desc.sizesInOrder, showAdd: false)
                                }
                                .buttonStyle(.plain)
                                // Permanently abandon: re-attaching is one tap above; this drops it for
                                // good (its .md is kept on disk, marked deprecated).
                                .overlay(alignment: .topTrailing) {
                                    Button(role: .destructive) { abandonTarget = slot } label: {
                                        Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                                            .padding(6).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).padding(6)
                                    .help("Abandon this tool (keeps its notes on disk, marked deprecated)")
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 380)
        }
        .padding(20)
        .frame(width: 380)
        .glassCard()
        .confirmationDialog("Abandon this tool?",
                            isPresented: Binding(get: { abandonTarget != nil }, set: { if !$0 { abandonTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Abandon", role: .destructive) {
                if let slot = abandonTarget { model.abandonTool(projectRef, slotID: slot.id) }
                abandonTarget = nil
            }
            Button("Cancel", role: .cancel) { abandonTarget = nil }
        } message: {
            Text("It's removed from the project for good. Its notes stay on disk (marked deprecated), so nothing is lost.")
        }
        .confirmationDialog("Uninstall this tool?",
                            isPresented: Binding(get: { uninstallTarget != nil }, set: { if !$0 { uninstallTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) {
                if let tool = uninstallTarget { model.uninstallTool(tool) }
                uninstallTarget = nil
            }
            Button("Cancel", role: .cancel) { uninstallTarget = nil }
        } message: {
            Text("Its .js is removed from the vault. Any cards it created stay on disk in the project.")
        }
        #if !os(macOS)
        .fileImporter(isPresented: $importingTool, allowedContentTypes: [.javaScript]) { result in
            if case .success(let url) = result { _ = model.installTool(from: url) }
        }
        #endif
    }

    /// Imports an installed-tool `.js` into the vault's `_tools/`. NSOpenPanel on macOS (its completion
    /// fires reliably even when this panel is presented inside an overlay); `.fileImporter` on iOS.
    private func importTool() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.javaScript]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            _ = model.installTool(from: url)
        }
        #else
        importingTool = true
        #endif
    }

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func card(icon: String, name: String, summary: LocalizedStringKey,
                      sizes: [ToolSize], showAdd: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
                Text(name).font(.body.weight(.medium))
                Spacer()
                // The whole card adds on tap, so the "+" is just an affordance — dropped on project
                // tools to make room for the abandon (trash) button that lives in that corner.
                if showAdd { Image(systemName: "plus.circle").foregroundStyle(.secondary) }
            }
            Text(summary)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) { ForEach(sizes, id: \.self) { sizePill($0.rawValue) } }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: NidusRadius.inner))
        .overlay(RoundedRectangle(cornerRadius: NidusRadius.inner)
            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func sizePill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private func addTemplate(_ tool: ToolDescriptor) {
        Haptics.tap()
        model.addTool(projectRef, toolID: tool.id, atCol: area.col, row: area.row,
                      areaCols: area.cols, areaRows: area.rows)
        onClose()
    }

    private func attach(_ slot: ToolSlot) {
        Haptics.tap()
        model.attachTool(projectRef, slotID: slot.id, atCol: area.col, row: area.row,
                         areaCols: area.cols, areaRows: area.rows)
        onClose()
    }
}
