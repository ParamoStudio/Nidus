//
//  MicroToolViews.swift
//  Nidus
//
//  The micro-tools UI that lives in a card's edit mode: a floating column bottom-right (collapsed to
//  a hint when not editing, expanded upward when editing — installed tools, with an import "+" on
//  top), and the runner popup that renders a tool's schema as a form and copies its Markdown output
//  to the clipboard for pasting into the note. All flat/glass, consistent with the rest of the app.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Puts `text` on the system clipboard (so the user can ⌘V it into the note).
func nidusCopyToClipboard(_ text: String) {
    #if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #elseif canImport(UIKit)
    UIPasteboard.general.string = text
    #endif
}

// MARK: - Floating bar (collapsed hint → expands upward in edit mode)

struct MicroToolBar: View {
    let tools: [MicroTool]
    let expanded: Bool                 // card is in edit mode
    let onRun: (MicroTool) -> Void
    let onManage: () -> Void
    let onDelete: (MicroTool) -> Void

    @State private var hoverAnchor = false

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            if expanded {
                // The manage/import control is topmost; installed tools sit between it and the anchor.
                // The manager panel itself is presented by the caller as a full overlay, NOT a
                // `.popover` — a `.popover`'s AppKit window teardown races the `.fileImporter` it hands
                // off to on Import, and the file picker gets silently swallowed.
                MicroCircleButton(system: "plus", label: "Manage micro-tools", action: onManage)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                ForEach(tools) { tool in
                    MicroCircleButton(system: tool.icon, label: tool.name) { onRun(tool) }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            anchor
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: expanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: tools)
    }

    /// The always-present signifier at the bottom: subtle when collapsed, lit when the column is open.
    private var anchor: some View {
        Image(systemName: "puzzlepiece.extension")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(expanded ? Color.primary : Color.secondary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().strokeBorder(Color.white.opacity(expanded || hoverAnchor ? 0.5 : 0.22)))
            .opacity(expanded ? 1 : 0.55)
            .scaleEffect(hoverAnchor ? 1.06 : 1)
            .onHover { hoverAnchor = $0 }
            .animation(.easeOut(duration: 0.15), value: hoverAnchor)
            .help(expanded ? "Micro-tools" : "Micro-tools — enter Edit to use them")
    }
}

/// One round tool button — flat, with a hover lift + glow. On hover it reveals its name in a pill to
/// the RIGHT (the bar lives just outside the card's right edge, so there's room there).
private struct MicroCircleButton: View {
    let system: String
    let label: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .medium)).foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(hover ? 0.7 : 0.4), lineWidth: 1.5))
                .shadow(color: .white.opacity(hover ? 0.22 : 0.10), radius: hover ? 12 : 7)
                .scaleEffect(hover ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            if hover {
                Text(label)
                    .font(.caption.weight(.medium)).foregroundStyle(.primary).fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
                    .offset(x: 52)                 // just to the right of the 44pt circle
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.16), value: hover)
    }
}

// MARK: - Manager (list of installed micro-tools: delete user ones, import new ones)

struct MicroToolManager: View {
    let tools: [MicroTool]
    var errorMessage: String? = nil
    let onImport: () -> Void
    let onDelete: (MicroTool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Micro-tools")
                .font(.headline)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }

            if tools.isEmpty {
                Text("None installed yet.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            } else {
                ForEach(tools) { tool in
                    HStack(spacing: 11) {
                        Image(systemName: tool.icon).font(.callout).foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.name).font(.callout.weight(.medium))
                            if tool.isBuiltIn {
                                Text("Built-in").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        if tool.isBuiltIn {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary)
                                .help("Built-in — always available")
                        } else {
                            Button(role: .destructive) { onDelete(tool) } label: {
                                Image(systemName: "trash").font(.callout).foregroundStyle(.secondary)
                            }.buttonStyle(.plain).help("Uninstall")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    Divider().opacity(0.4)
                }
            }

            Button(action: onImport) {
                Label("Import micro-tool (.js)", systemImage: "square.and.arrow.down")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 340)
        .padding(.vertical, 6)
        // Its own card container, like the rest of the app (it's presented over a dimmed backdrop).
        .glassCard()
        .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
    }
}

// MARK: - Runner popup (schema-driven form → Markdown to clipboard)

private struct MicroRow: Identifiable { let id = UUID(); var cells: [String: String] }

struct MicroToolRunnerView: View {
    let tool: MicroTool
    let onClose: () -> Void

    @State private var scalars: [String: String] = [:]
    @State private var tables: [String: [MicroRow]] = [:]
    @State private var grids: [String: [[String]]] = [:]
    @State private var gridUnits: [String: [String]] = [:]   // per-grid, per-column unit (g, %, …)
    @State private var pickerExpanded: Set<String> = []      // which "list" pickers are open
    @State private var batchPrefix: [String: String] = [:]   // batch: the code prefix (e.g. "Nm")
    @State private var batchRows: [String: [[String]]] = [:] // batch: per-item column values
    @State private var copied = false
    @State private var previewMeasured: CGSize = .zero

    // The editor popup and a SEPARATE floating preview card anchored contiguously to its right.
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            editorCard
            previewCard
        }
        .onAppear(perform: seed)
    }

    private var editorCard: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Conditional fields: only show an input whose `showWhen` matches the current state.
                    ForEach(tool.inputs.filter(isVisible)) { input in inputView(input) }
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 480, height: 552)
        .glassCard()
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})   // taps on chrome don't fall through to dismiss
        .background(Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
    }

    /// The floating live-preview annex. It starts small (top-right of the editor) and GROWS DOWN with
    /// its content up to a cap, then scrolls — no big empty card, no "lazy" scroll from the start. The
    /// width is fixed on purpose: growing it per-keystroke would jitter the whole popup sideways; wide
    /// tables scroll horizontally inside instead.
    private var previewCard: some View {
        // Grows with its content (both ways) up to a cap, then scrolls — starts small, no empty card.
        let width = min(max(previewMeasured.width + 36, 220), 600)
        let height = min(max(previewMeasured.height + 108, 150), 640)
        return VStack(spacing: 0) {
            HStack {
                Text("Live preview").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 15).padding(.bottom, 8)

            ScrollView([.vertical, .horizontal]) {
                previewContent
                    .padding(.horizontal, 18).padding(.bottom, 16)
            }
            .scrollIndicators(.never)

            Divider().opacity(0.4)
            HStack(spacing: 10) {
                Text("Paste (⌘V) into your note.").font(.caption2).foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Button(action: copy) {
                    Label(copied ? "Copied ✓" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: width, height: height)
        .glassCard()
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})
        .animation(.easeOut(duration: 0.18), value: previewMeasured)
        // Off-screen measurer: reports the content's natural size so the card can size to it.
        .background(
            previewContent.fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { previewMeasured = $0 }
                .hidden().allowsHitTesting(false)
        )
    }

    @ViewBuilder private var previewContent: some View {
        let md = markdown
        if md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Your Markdown preview appears here.")
                .font(.callout).foregroundStyle(.tertiary)
                .frame(width: 200, alignment: .leading)
        } else {
            MarkdownView(blocks: MarkdownParser.parse(md))
                .fixedSize()   // take natural size (wide tables scroll) instead of truncating to fit
        }
    }

    private var markdown: String { MicroToolEngine.render(tool, data: buildData()) ?? "" }

    private func buildData() -> [String: Any] {
        var data: [String: Any] = [:]
        for input in tool.inputs {
            switch input.kind {
            case .table:
                data[input.key] = rows(input.key).map { $0.cells }
            case .grid:
                // Fold each column's unit into its non-empty data cells (header row kept clean).
                let g = grids[input.key] ?? []
                let u = gridUnits[input.key] ?? []
                data[input.key] = g.enumerated().map { r, row in
                    row.enumerated().map { c, val in
                        let unit = c < u.count ? u[c].trimmingCharacters(in: .whitespaces) : ""
                        let v = val.trimmingCharacters(in: .whitespaces)
                        return (r > 0 && !unit.isEmpty && !v.isEmpty) ? v + " " + unit : val
                    }
                }
            case .row:
                for f in input.fields { data[f.key] = scalars[f.key] ?? "" }
            case .batch:
                let bRows = batchRows[input.key] ?? []
                let items: [[String: Any]] = bRows.enumerated().map { idx, row in
                    var item: [String: Any] = ["n": idx + 1]
                    for (ci, col) in input.columns.enumerated() {
                        item[col.key] = ci < row.count ? row[ci] : ""
                    }
                    return item
                }
                data[input.key] = ["prefix": batchPrefix[input.key] ?? "", "items": items]
            default:
                data[input.key] = scalars[input.key] ?? ""
            }
        }
        return data
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: tool.icon).font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name).font(.title3.weight(.semibold))
                if !tool.summary.isEmpty {
                    Text(tool.summary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)   // wrap fully, never truncate
                }
            }
            Spacer(minLength: 8)
            Button { onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 30, height: 30).background(Circle().fill(Color.primary.opacity(0.07)))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 12)
    }

    // MARK: Inputs

    @ViewBuilder private func inputView(_ input: MicroInput) -> some View {
        if input.kind == .row {
            // Several scalar fields on one line (e.g. a corner's name + its max %), each with its label.
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(input.fields) { f in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(f.label.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                        scalarField(f, axis: .horizontal, lines: 1...1)
                    }
                    .frame(maxWidth: f.kind == .number ? 96 : .infinity, alignment: .leading)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(input.label.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                switch input.kind {
                case .table:    tableView(input)
                case .grid:     GridEditor(grid: gridBinding(input.key), units: gridUnitsBinding(input.key))
                case .batch:    BatchEditor(prefix: batchPrefixBinding(input.key),
                                            rows: batchRowsBinding(input.key), columns: input.columns)
                case .picker:   pickerView(input)
                case .textarea: scalarField(input, axis: .vertical, lines: 2...6)
                default:        scalarField(input, axis: .horizontal, lines: 1...1)
                }
            }
        }
    }

    /// An input is visible unless its `showWhen` references a field whose current value doesn't match.
    private func isVisible(_ input: MicroInput) -> Bool {
        guard let cond = input.showWhen else { return true }
        return cond.values.contains(scalars[cond.key] ?? "")
    }

    /// A picker (template/preset chooser). `style` picks the presentation; all set the same string
    /// value that drives conditional (`showWhen`) fields.
    @ViewBuilder private func pickerView(_ input: MicroInput) -> some View {
        switch input.pickerStyle {
        case "chips", "tabs", "segmented": pickerChips(input)
        case "menu", "dropdown", "select": pickerMenu(input)
        default:                            pickerList(input)   // "list"/"accordion"/"collapsible"
        }
    }

    private func selectPicker(_ input: MicroInput, _ value: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            scalars[input.key] = value
            pickerExpanded.remove(input.key)   // collapse to the chosen name
        }
    }

    /// The default: opens EXPANDED as a list (choose first); once chosen it collapses to the selected
    /// name; tapping that name re-expands the full list. Best for many options (e.g. a template library).
    private func pickerList(_ input: MicroInput) -> some View {
        let current = scalars[input.key] ?? ""
        let selectedLabel = input.options.first { $0.value == current }?.label
        let expanded = current.isEmpty || pickerExpanded.contains(input.key)
        return VStack(alignment: .leading, spacing: 8) {
            if let selectedLabel {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if pickerExpanded.contains(input.key) { pickerExpanded.remove(input.key) }
                        else { pickerExpanded.insert(input.key) }
                    }
                } label: {
                    HStack {
                        Text(selectedLabel).font(.callout.weight(.semibold))
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(0.3)))
                }.buttonStyle(.plain)
            }
            if expanded {
                VStack(spacing: 2) {
                    ForEach(input.options) { opt in
                        let on = opt.value == current
                        Button { selectPicker(input, opt.value) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt.label).font(.callout).foregroundStyle(.primary)
                                    if !opt.description.isEmpty {
                                        Text(opt.description).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if on { Image(systemName: "checkmark").font(.caption).foregroundStyle(Color.accentColor) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(on ? 0.06 : 0)))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
        }
    }

    /// A compact dropdown menu — good when the picker should stay small.
    private func pickerMenu(_ input: MicroInput) -> some View {
        let current = scalars[input.key] ?? ""
        let selectedLabel = input.options.first { $0.value == current }?.label
        return Menu {
            ForEach(input.options) { opt in
                Button(opt.label) { scalars[input.key] = opt.value }
            }
        } label: {
            HStack {
                Text(selectedLabel ?? "Choose…").font(.callout).foregroundStyle(selectedLabel == nil ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9).background(fieldBg())
        }.menuStyle(.borderlessButton)
    }

    /// A row of preset chips/tabs — good for a handful of options.
    private func pickerChips(_ input: MicroInput) -> some View {
        let current = scalars[input.key] ?? ""
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(input.options) { opt in
                    let on = current == opt.value
                    Button { scalars[input.key] = opt.value } label: {
                        Text(opt.label).font(.callout.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color.accentColor.opacity(on ? 0.18 : 0.06)))
                            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(on ? 0.6 : 0), lineWidth: 1))
                            .foregroundStyle(on ? .primary : .secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func scalarField(_ input: MicroInput, axis: Axis, lines: ClosedRange<Int>) -> some View {
        TextField(input.placeholder, text: scalarBinding(input.key, maxLength: input.maxLength), axis: axis)
            .textFieldStyle(.plain).font(.callout).lineLimit(lines)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(fieldBg())
            #if os(iOS)
            .autocorrectionDisabled()
            .keyboardType(input.kind == .number ? .numbersAndPunctuation : .default)
            #endif
    }

    private func tableView(_ input: MicroInput) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(input.columns) { col in
                    Text(col.label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Color.clear.frame(width: 24)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            ForEach(rows(input.key)) { row in
                HStack(spacing: 8) {
                    ForEach(input.columns) { col in
                        TextField(col.numeric ? "0" : "", text: cellBinding(input.key, row.id, col.key))
                            .textFieldStyle(.plain).font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Return on the last row adds another (spreadsheet feel).
                            .onSubmit { if rows(input.key).last?.id == row.id { addRow(input) } }
                            #if os(iOS)
                            .keyboardType(col.numeric ? .decimalPad : .default)
                            .autocorrectionDisabled()
                            #endif
                    }
                    Button { removeRow(input.key, row.id) } label: {
                        Image(systemName: "minus.circle").font(.callout).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain).frame(width: 24)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                Divider().opacity(0.35)
            }

            Button { addRow(input) } label: {
                Label(input.addLabel, systemImage: "plus").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 9)
            }.buttonStyle(.plain)
        }
        .background(fieldBg())
    }

    private func fieldBg() -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10)))
    }

    // MARK: State plumbing

    private func seed() {
        for input in tool.inputs {
            switch input.kind {
            case .table:
                if tables[input.key] == nil { tables[input.key] = [emptyRow(input)] }
            case .grid:
                if grids[input.key] == nil {
                    grids[input.key] = Array(repeating: Array(repeating: "", count: input.gridCols),
                                             count: input.gridRows)
                }
                if gridUnits[input.key] == nil {
                    gridUnits[input.key] = Array(repeating: "", count: input.gridCols)
                }
            case .batch:
                if batchPrefix[input.key] == nil { batchPrefix[input.key] = "" }
                if batchRows[input.key] == nil {
                    batchRows[input.key] = (0..<5).map { _ in Array(repeating: "", count: input.columns.count) }
                }
            case .picker:
                break   // no auto-selection: the list picker opens expanded so you choose first
            default: break
            }
        }
    }

    private func emptyRow(_ input: MicroInput) -> MicroRow {
        MicroRow(cells: Dictionary(uniqueKeysWithValues: input.columns.map { ($0.key, "") }))
    }

    private func rows(_ key: String) -> [MicroRow] { tables[key] ?? [] }

    private func addRow(_ input: MicroInput) {
        tables[input.key, default: []].append(emptyRow(input))
    }
    private func removeRow(_ key: String, _ id: UUID) {
        tables[key]?.removeAll { $0.id == id }
    }

    private func scalarBinding(_ key: String, maxLength: Int = 0) -> Binding<String> {
        Binding(
            get: { scalars[key] ?? "" },
            set: { scalars[key] = (maxLength > 0) ? String($0.prefix(maxLength)) : $0 })
    }
    private func gridBinding(_ key: String) -> Binding<[[String]]> {
        Binding(get: { grids[key] ?? [] }, set: { grids[key] = $0 })
    }
    private func gridUnitsBinding(_ key: String) -> Binding<[String]> {
        Binding(get: { gridUnits[key] ?? [] }, set: { gridUnits[key] = $0 })
    }
    private func batchPrefixBinding(_ key: String) -> Binding<String> {
        Binding(get: { batchPrefix[key] ?? "" }, set: { batchPrefix[key] = $0 })
    }
    private func batchRowsBinding(_ key: String) -> Binding<[[String]]> {
        Binding(get: { batchRows[key] ?? [] }, set: { batchRows[key] = $0 })
    }
    private func cellBinding(_ key: String, _ rowID: UUID, _ col: String) -> Binding<String> {
        Binding(
            get: { tables[key]?.first { $0.id == rowID }?.cells[col] ?? "" },
            set: { new in
                guard let i = tables[key]?.firstIndex(where: { $0.id == rowID }) else { return }
                tables[key]?[i].cells[col] = new
            })
    }

    private func copy() {
        guard let md = MicroToolEngine.render(tool, data: buildData()) else { return }
        nidusCopyToClipboard(md)
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            onClose()
        }
    }
}

// MARK: - Editable grid widget (host-drawn; the `grid` input type)

/// An editable table that starts small and grows both ways (+ Row / + Column). Cells are plain text;
/// the first row is the header (styled). The micro-tool receives it as a 2D array of strings and
/// turns it into Markdown — all interactivity lives here in the host, the JS stays pure.
private struct GridEditor: View {
    @Binding var grid: [[String]]
    @Binding var units: [String]           // per-column unit; shown as a fixed chip on data cells

    private let colW: CGFloat = 118
    private let rowCtrlW: CGFloat = 26     // left gutter: move-up / delete / move-down
    private var cols: Int { grid.first?.count ?? 0 }
    private var rows: Int { grid.count }

    // Deliberate per-column unit: the ruler button targets a column, you type a unit, apply.
    @State private var unitColumn: Int?
    @State private var unitDraft = ""
    @FocusState private var unitFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let c = unitColumn { unitPrompt(c) }

            // Horizontal scroll so lots of columns stay comfortable (each keeps a usable width).
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 5) {
                    columnControls
                    ForEach(Array(grid.indices), id: \.self) { r in
                        HStack(spacing: 5) {
                            rowControls(r)
                            ForEach(Array(0..<cols), id: \.self) { c in
                                HStack(spacing: 4) {
                                    TextField(r == 0 ? "Header" : "", text: cell(r, c))
                                        .textFieldStyle(.plain)
                                        .font(r == 0 ? .callout.weight(.semibold) : .callout)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .onSubmit { if r == grid.count - 1 { addRow() } }  // Return = new row
                                        #if os(iOS)
                                        .autocorrectionDisabled()
                                        #endif
                                    // The column's unit sits fixed on the right of each data cell,
                                    // matching how it reads in the exported table ("10 g").
                                    if r > 0, unit(c) != "" {
                                        Text(unit(c)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 7)
                                .frame(width: colW, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(cellFill(r, c)))
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            HStack(spacing: 8) {
                gridButton("Row", "plus") { addRow() }
                gridButton("Column", "plus") { addColumn() }
                columnCountMenu
            }
        }
    }

    /// Pick the number of columns directly (go straight to N instead of clicking +Column repeatedly,
    /// so the layout settles in one step). Capped at 8 — plenty for a simple app.
    private var columnCountMenu: some View {
        Menu {
            ForEach(Array(1...8), id: \.self) { n in
                Button("\(n) column\(n == 1 ? "" : "s")") { setColumnCount(n) }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(cols)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Number of columns")
    }

    /// The deliberate unit bar: shown after a double-click. Appends the unit to that column's filled
    /// cells (header excluded); values you didn't fill stay empty, and you can still edit any cell.
    private func unitPrompt(_ c: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "ruler").font(.caption).foregroundStyle(.secondary)
            Text("Apply unit to selected column").font(.caption).foregroundStyle(.secondary)
            TextField("g, %, ml…", text: $unitDraft)
                .textFieldStyle(.plain).font(.callout).frame(width: 90)
                .focused($unitFocused)
                .onSubmit { applyUnit(c) }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                #if os(iOS)
                .autocorrectionDisabled()
                #endif
            Button("Apply") { applyUnit(c) }.buttonStyle(.plain).font(.callout.weight(.medium))
                .foregroundStyle(Color.accentColor)
            Button("Cancel") { cancelUnit() }.buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor.opacity(0.25)))
    }

    private func cellFill(_ r: Int, _ c: Int) -> Color {
        if unitColumn == c && r > 0 { return Color.accentColor.opacity(0.14) }   // targeted column
        return Color.primary.opacity(r == 0 ? 0.08 : 0.04)
    }

    private func unit(_ c: Int) -> String { c < units.count ? units[c] : "" }

    private func beginUnit(_ c: Int) {
        unitColumn = c
        unitDraft = unit(c)   // prefill with the current unit so it's editable/removable
        DispatchQueue.main.async { unitFocused = true }
    }
    private func cancelUnit() { unitColumn = nil; unitDraft = "" }

    /// Sets (or clears) the whole column's unit. It shows as a fixed chip on every data cell and is
    /// folded into the exported values — the raw cell text you type stays just the value.
    private func applyUnit(_ c: Int) {
        while units.count < cols { units.append("") }   // keep units sized to the columns
        if units.indices.contains(c) { units[c] = unitDraft.trimmingCharacters(in: .whitespaces) }
        cancelUnit()
    }

    /// Per-column controls, centered over each column: ‹ swap-left · − delete · › swap-right · unit.
    /// The unit button (a reliable tap, unlike double-clicking an editable field) opens the unit bar.
    private var columnControls: some View {
        HStack(spacing: 5) {
            Color.clear.frame(width: rowCtrlW)   // align with the row gutter on the left
            ForEach(Array(0..<cols), id: \.self) { c in
                HStack(spacing: 2) {
                    ctrl("chevron.left", enabled: c > 0, help: "Move column left") { swapColumns(c, c - 1) }
                    ctrl("minus", enabled: cols > 1, help: "Delete column") { deleteColumn(c) }
                    ctrl("chevron.right", enabled: c < cols - 1, help: "Move column right") { swapColumns(c, c + 1) }
                    ctrl("ruler", enabled: true, help: "Add a unit to this column") { beginUnit(c) }
                }
                .frame(width: colW, height: 16)
            }
        }
    }

    /// Per-row controls in the left gutter: ∧ move-up · − delete · ∨ move-down.
    private func rowControls(_ r: Int) -> some View {
        VStack(spacing: 1) {
            ctrl("chevron.up", enabled: r > 0) { swapRows(r, r - 1) }
            ctrl("minus", enabled: rows > 1) { removeRow(r) }
            ctrl("chevron.down", enabled: r < rows - 1) { swapRows(r, r + 1) }
        }
        .frame(width: rowCtrlW)
    }

    /// A tiny control glyph — dimmed + inert when the action isn't available (keeps layout stable).
    private func ctrl(_ system: String, enabled: Bool, help: String = "", _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 0.9 : 0.2)
        .help(help)
    }

    private func gridButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func cell(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: { grid.indices.contains(r) && grid[r].indices.contains(c) ? grid[r][c] : "" },
            set: { if grid.indices.contains(r) && grid[r].indices.contains(c) { grid[r][c] = $0 } })
    }

    private func addRow() { grid.append(Array(repeating: "", count: max(cols, 1))) }
    private func addColumn() {
        guard cols < 8 else { return }
        for i in grid.indices { grid[i].append("") }
        units.append("")
    }
    private func removeLastColumn() {
        guard cols > 1 else { return }
        for i in grid.indices where !grid[i].isEmpty { grid[i].removeLast() }
        if !units.isEmpty { units.removeLast() }
    }
    private func setColumnCount(_ n: Int) {
        let target = min(max(n, 1), 8)
        while cols < target { addColumn() }
        while cols > target { removeLastColumn() }
    }
    private func removeRow(_ r: Int) { if grid.count > 1, grid.indices.contains(r) { grid.remove(at: r) } }
    private func deleteColumn(_ c: Int) {
        guard cols > 1 else { return }
        for i in grid.indices where grid[i].indices.contains(c) { grid[i].remove(at: c) }
        if units.indices.contains(c) { units.remove(at: c) }
    }
    private func swapRows(_ a: Int, _ b: Int) {
        guard grid.indices.contains(a), grid.indices.contains(b) else { return }
        grid.swapAt(a, b)
    }
    private func swapColumns(_ a: Int, _ b: Int) {
        for i in grid.indices where grid[i].indices.contains(a) && grid[i].indices.contains(b) {
            grid[i].swapAt(a, b)
        }
        if units.indices.contains(a), units.indices.contains(b) { units.swapAt(a, b) }
    }
}

// MARK: - Batch widget (a numbered series of items with editable attributes; the `batch` input type)

/// A code prefix + a count → N rows, each with its auto-generated code label (a hint) and editable
/// cells for the schema's columns. The tool composes the final code in `render`; here we just show a
/// live hint. Rows keep their values as the count grows/shrinks.
private struct BatchEditor: View {
    @Binding var prefix: String
    @Binding var rows: [[String]]
    let columns: [MicroColumn]

    @State private var countText = ""
    @FocusState private var countFocused: Bool

    private func codeHint(_ i: Int) -> String { prefix.isEmpty ? "#\(i + 1)" : "\(prefix)-\(i + 1)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                labelled("Code") {
                    TextField("Nm", text: $prefix)
                        .textFieldStyle(.plain).font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 8).background(fieldBg())
                        #if os(iOS)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        #endif
                }
                labelled("How many") {
                    HStack(spacing: 6) {
                        TextField("5", text: $countText)
                            .textFieldStyle(.plain).font(.callout).frame(width: 40)
                            .multilineTextAlignment(.center)
                            .focused($countFocused)
                            .onSubmit { resize(Int(countText) ?? rows.count) }
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Stepper("", onIncrement: { resize(rows.count + 1) },
                                    onDecrement: { resize(rows.count - 1) }).labelsHidden()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5).background(fieldBg())
                }
                .fixedSize()
            }

            // Column headers (Code + the schema columns).
            HStack(spacing: 8) {
                Text("Code").font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
                ForEach(columns) { col in
                    Text(col.label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 4).padding(.top, 2)

            ForEach(Array(rows.indices), id: \.self) { r in
                HStack(spacing: 8) {
                    Text(codeHint(r)).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                        .frame(width: 66, alignment: .leading).lineLimit(1)
                    ForEach(Array(columns.indices), id: \.self) { c in
                        TextField("", text: cell(r, c))
                            .textFieldStyle(.plain).font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.04)))
                            #if os(iOS)
                            .autocorrectionDisabled()
                            #endif
                    }
                }
            }
        }
        .onAppear { countText = String(rows.count) }
    }

    private func labelled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: title == "Code" ? .infinity : nil, alignment: .leading)
    }

    private func fieldBg() -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
    }

    private func cell(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: { rows.indices.contains(r) && rows[r].indices.contains(c) ? rows[r][c] : "" },
            set: { if rows.indices.contains(r) && rows[r].indices.contains(c) { rows[r][c] = $0 } })
    }

    private func resize(_ n: Int) {
        let target = min(max(n, 1), 50)
        while rows.count < target { rows.append(Array(repeating: "", count: columns.count)) }
        while rows.count > target { rows.removeLast() }
        countText = String(target)
    }
}
