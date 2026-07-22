//
//  InstalledToolViews.swift
//  Nidus
//
//  Paints an installed tool's declarative view TREES (returned by its `tile`/`expanded`/`card` JS
//  functions) with native SwiftUI, using the recycled primitive vocabulary from the spec (stack,
//  text, markdown, badge, divider, spacer, cardList, button, form, html…). Handlers are wired back to
//  the JS engine; after one runs, the view re-renders from the tool's (now-updated) cards.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Render context passed down the tree

struct NodeContext {
    let run: InstalledToolEngine.Run
    let baseURL: URL?                              // folder, for relative images / html asset paths
    let onHandler: (String, [String: Any]) -> Void // run a handler by name + payload, then refresh
}

// MARK: - Dictionary helpers (JS objects arrive as [AnyHashable: Any])

private func asDict(_ any: Any?) -> [String: Any]? {
    if let d = any as? [String: Any] { return d }
    if let d = any as? [AnyHashable: Any] {
        var out: [String: Any] = [:]
        for (k, v) in d { out[String(describing: k)] = v }
        return out
    }
    return nil
}
private func asArray(_ any: Any?) -> [Any] { (any as? [Any]) ?? [] }
private func str(_ d: [String: Any], _ k: String) -> String? { d[k] as? String }

/// Resolves an image path to a URL. Absolute paths (bank entries, stored as "/…") load directly; relative
/// paths ("_assets/…") resolve against the tool's folder.
private func resolveImage(_ base: URL?, _ rel: String) -> URL? {
    rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : base?.appendingPathComponent(rel)
}

// MARK: - The recursive renderer

struct NodeView: View {
    let node: Any?
    let ctx: NodeContext

    var body: some View {
        if let arr = node as? [Any] {
            // A bare array → a vertical stack of its nodes.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(arr.enumerated()), id: \.offset) { _, child in
                    NodeView(node: child, ctx: ctx)
                }
            }
        } else if let d = asDict(node) {
            render(d)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder private func render(_ d: [String: Any]) -> some View {
        switch str(d, "type") ?? "" {
        case "stack":     stackView(d)
        case "section":   sectionView(d)
        case "text":      textView(d)
        case "markdown":  MarkdownView(blocks: MarkdownParser.parse(str(d, "value") ?? ""), baseURL: ctx.baseURL)
        case "badge":     badgeView(d)
        case "field":     labeledField(d)
        case "divider":   Divider().opacity(0.4)
        case "spacer":    Spacer(minLength: 0)
        case "image":     imageView(d)
        case "gallery":   galleryView(d)
        case "table":     NodeTable(d: d)
        case "cardList":  NodeCardList(d: d, ctx: ctx)
        case "cardGrid":  NodeCardGrid(d: d, ctx: ctx)
        case "button":    buttonView(d)
        case "form":      NodeForm(d: d, ctx: ctx)
        case "grid":      gridView(d)
        case "html":      InstalledToolWebView(html: str(d, "html") ?? "",
                                               height: (d["height"] as? NSNumber)?.doubleValue,
                                               network: (d["network"] as? Bool) ?? false,
                                               run: ctx.run)
        default:          EmptyView()
        }
    }

    /// A titled panel — gives a region its own bordered section (like the app's own cards), instead of
    /// content "thrown on top" of the view.
    @ViewBuilder private func sectionView(_ d: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = str(d, "title") {
                Text(title).font(.headline)
            }
            ForEach(Array(children(d).enumerated()), id: \.offset) { _, c in NodeView(node: c, ctx: ctx) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    /// A read-only labeled value pair (e.g. "Cone   6") — for card details.
    private func labeledField(_ d: [String: Any]) -> some View {
        HStack {
            Text((str(d, "label") ?? "").uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            Spacer()
            Text(str(d, "value") ?? "").font(.callout.weight(.medium))
        }
    }

    private func children(_ d: [String: Any]) -> [Any] { asArray(d["children"]) }

    @ViewBuilder private func stackView(_ d: [String: Any]) -> some View {
        let spacing = (d["spacing"] as? NSNumber)?.doubleValue ?? 10
        let kids = children(d)
        if (str(d, "axis") ?? "v") == "h" {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(kids.enumerated()), id: \.offset) { _, c in NodeView(node: c, ctx: ctx) }
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(kids.enumerated()), id: \.offset) { _, c in NodeView(node: c, ctx: ctx) }
            }
        }
    }

    private func textView(_ d: [String: Any]) -> some View {
        let value = str(d, "value") ?? ""
        let font: Font
        switch str(d, "style") ?? "body" {
        case "title":   font = .title2.weight(.bold)
        case "heading": font = .headline
        case "caption": font = .caption
        default:        font = .body
        }
        return Text(value).font(font)
            .foregroundStyle((str(d, "style") == "caption") ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func badgeView(_ d: [String: Any]) -> some View {
        Text(str(d, "value") ?? "").font(.caption2.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder private func imageView(_ d: [String: Any]) -> some View {
        if let src = str(d, "src") {
            MarkdownView(blocks: [.image(src: src, alt: str(d, "alt") ?? "")], baseURL: ctx.baseURL)
        }
    }

    /// A row of image thumbnails from an array of (relative or remote) srcs.
    @ViewBuilder private func galleryView(_ d: [String: Any]) -> some View {
        let srcs = asArray(d["images"]).map { "\($0)" }
        if !srcs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(srcs.enumerated()), id: \.offset) { _, src in
                        if let url = resolveImage(ctx.baseURL, src), let img = nidusLoadImage(at: url) {
                            img.resizable().scaledToFill().frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func gridView(_ d: [String: Any]) -> some View {
        let cols = max(1, (d["columns"] as? NSNumber)?.intValue ?? 2)
        let kids = children(d)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: cols), spacing: 10) {
            ForEach(Array(kids.enumerated()), id: \.offset) { _, c in NodeView(node: c, ctx: ctx) }
        }
    }

    private func buttonView(_ d: [String: Any]) -> some View {
        let label = str(d, "label") ?? ""
        let icon = str(d, "icon")
        let handler = str(d, "onTap")
        let payload = asDict(d["with"]) ?? [:]   // static data to hand the handler (e.g. a card id)
        let destructive = str(d, "role") == "destructive"
        return Button {
            if let handler { ctx.onHandler(handler, payload) }
        } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                if !label.isEmpty { Text(label) }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(destructive ? Color.red : Color.accentColor)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill((destructive ? Color.red : Color.accentColor).opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - cardList

private struct NodeCardList: View {
    let d: [String: Any]
    let ctx: NodeContext

    @Environment(NidusModel.self) private var model
    @Environment(CardDragController.self) private var drag

    private var wanted: [String] { asArray(d["cards"]).compactMap { asDict($0) }.compactMap { str($0, "id") } }
    private var onTap: String? { str(d, "onTap") }
    private var subtitleKey: String? { str(d, "subtitle") }   // an `extra` field to show as the subtitle

    private var cards: [Card] {
        guard let file = ctx.run.primaryFile else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: CardStore.read(from: file).map { ($0.id, $0) })
        return wanted.compactMap { byID[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if cards.isEmpty {
                Text("Nothing here yet.").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(cards) { card in row(card) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A clean, compact card row: thumbnail + title + subtitle (an extra field) + date. NO raw body.
    /// Draggable to other tools (bidirectional) and tappable to open.
    private func row(_ card: Card) -> some View {
        let subtitleField = subtitleKey.flatMap { card.extra[$0] }
        let date = NotebookIcon.relativeEdited(card.modified)
        let subtitle = [subtitleField, date].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                if let rel = card.images.first, let url = resolveImage(ctx.baseURL, rel), let img = nidusLoadImage(at: url) {
                    img.resizable().scaledToFill()
                } else {
                    Image(systemName: ctx.run.tool.manifest.icon).font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title).font(.callout.weight(.medium)).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture { if let onTap { ctx.onHandler(onTap, ["id": card.id]) } }
        // Cross-tool drag-out (same controller the native tools use). Drop-in is handled by the tile.
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("workspace"))
                .onChanged { value in
                    guard let src = ctx.run.primaryFile else { return }
                    if drag.dragging == nil {
                        drag.begin(card: card, sourceFile: src, sourceTool: ctx.run.tool.id,
                                   folderURL: ctx.baseURL, at: value.location)
                    } else { drag.move(to: value.location) }
                }
                .onEnded { _ in drag.drop(model: model) }
        )
    }
}

// MARK: - cardGrid (photo tiles grouped by category, drag a tile between groups to recategorize)

private struct NodeCardGrid: View {
    let d: [String: Any]
    let ctx: NodeContext

    private var cardDicts: [[String: Any]] { asArray(d["cards"]).compactMap { asDict($0) } }
    private var groups: [[String: Any]] { asArray(d["groups"]).compactMap { asDict($0) } }
    private var groupBy: String { str(d, "groupBy") ?? "status" }
    private var badgeKey: String? { str(d, "badge") }
    private var onOpen: String? { str(d, "onOpen") }
    private var onMove: String? { str(d, "onMove") }

    private func extra(_ card: [String: Any]) -> [String: String] {
        (asDict(card["extra"]) ?? [:]).mapValues { "\($0)" }
    }

    // Manual drag (native .dropDestination proved unreliable inside the scrolling overlay). We track the
    // drag ourselves in a local coordinate space and hit-test the group frames — the WHOLE bordered zone
    // (header + grid) is the drop target, and it can never leak to background tools.
    private let space = "cardGrid"
    @State private var groupFrames: [String: CGRect] = [:]
    @State private var draggingID: String?
    @State private var dragLocation: CGPoint?
    @State private var hoverGroup: String?

    private func groupOf(_ id: String) -> String {
        cardDicts.first { str($0, "id") == id }.map { extra($0)[groupBy] ?? "" } ?? ""
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in groupSection(g) }
            }
            // A preview that follows the cursor, so the drag reads as a real move.
            if let draggingID, let loc = dragLocation,
               let card = cardDicts.first(where: { str($0, "id") == draggingID }) {
                Text(str(card, "title") ?? "Untitled")
                    .font(.caption.weight(.medium)).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5)))
                    .position(loc).allowsHitTesting(false).transition(.opacity)
            }
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(CardGridFrameKey.self) { groupFrames = $0 }
    }

    @ViewBuilder private func groupSection(_ g: [String: Any]) -> some View {
        let key = str(g, "key") ?? ""
        let inGroup = cardDicts.filter { extra($0)[groupBy] == key }
        let targeted = hoverGroup == key && draggingID != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(str(g, "label") ?? key).font(.headline)
                Text("\(inGroup.count)").font(.caption).foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(Array(inGroup.enumerated()), id: \.offset) { _, card in tile(card) }
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(targeted ? 0.14 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(targeted ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.06),
                          lineWidth: targeted ? 2 : 1))
        // Report this zone's frame so the drag can hit-test against it.
        .background(GeometryReader { geo in
            Color.clear.preference(key: CardGridFrameKey.self, value: [key: geo.frame(in: .named(space))])
        })
    }

    private func tile(_ card: [String: Any]) -> some View {
        let id = str(card, "id") ?? ""
        let title = str(card, "title") ?? "Untitled"
        let images = asArray(card["images"]).map { "\($0)" }
        let badge = badgeKey.flatMap { extra(card)[$0] }
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06))
                if let first = images.first, let url = resolveImage(ctx.baseURL, first), let img = nidusLoadImage(at: url) {
                    img.resizable().scaledToFill()
                } else {
                    Image(systemName: "circle.dashed").font(.title2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 116, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let badge, !badge.isEmpty {
                    Text(badge).font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.ultraThinMaterial)).padding(5)
                }
            }
            Text(title).font(.caption.weight(.medium)).lineLimit(1).frame(width: 116, alignment: .leading)
        }
        .opacity(draggingID == id ? 0.3 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if draggingID == nil, let onOpen { ctx.onHandler(onOpen, ["id": id]) } }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(space))
                .onChanged { v in
                    draggingID = id
                    dragLocation = v.location
                    hoverGroup = groupFrames.first { $0.value.contains(v.location) }?.key
                }
                .onEnded { v in
                    if let target = groupFrames.first(where: { $0.value.contains(v.location) })?.key,
                       let onMove, target != groupOf(id) {
                        ctx.onHandler(onMove, ["id": id, "group": target])
                    }
                    draggingID = nil; dragLocation = nil; hoverGroup = nil
                }
        )
    }
}

/// Group-key → frame (in the cardGrid's local space) so a manual drag can find its drop target.
private struct CardGridFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - table (read-only display, e.g. a recipe's materials + amounts)

private struct NodeTable: View {
    let d: [String: Any]
    private var headers: [String] { asArray(d["headers"]).map { "\($0)" } }
    private var rows: [[String]] { asArray(d["rows"]).map { r in asArray(r).map { "\($0)" } } }
    private var cols: Int { max(headers.count, 1) }

    var body: some View {
        // A gridded table with an outer border + row AND column separators — legible, not just spaced text.
        VStack(spacing: 0) {
            if !headers.isEmpty {
                row(headers, header: true)
                Divider().opacity(0.35)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                row(r, header: false)
                if idx < rows.count - 1 { Divider().opacity(0.12) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<cols, id: \.self) { j in
                cell(j < cells.count ? cells[j] : "")
                    .font(header ? .caption.weight(.semibold) : .callout)
                    .foregroundStyle(header ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity, alignment: j == 0 ? .leading : .trailing)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                if j < cols - 1 { Divider().opacity(0.10) }   // column separator
            }
        }
    }

    private func cell(_ s: String) -> Text {
        if let attr = try? AttributedString(markdown: s,
                                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }
}

// MARK: - form (renders the micro-tool input schema; submit → a handler)

private struct NodeForm: View {
    let d: [String: Any]
    let ctx: NodeContext
    @State private var values: [String: String] = [:]
    @State private var tables: [String: [[String]]] = [:]   // table inputs: key → rows of cell strings
    @State private var photos: [String: [String]] = [:]     // photos inputs: key → relative image paths
    @State private var loaded = false

    private var inputs: [[String: Any]] { asArray(d["inputs"]).compactMap { asDict($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(inputs.enumerated()), id: \.offset) { _, input in inputRow(input) }
            Button {
                if let submit = str(d, "submit") {
                    ctx.onHandler(submit, payload())
                    if asDict(d["with"]) == nil { values = [:]; tables = [:] }   // keep edit forms filled; clear "new" forms
                }
            } label: {
                Text(str(d, "submitLabel") ?? "Add")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .onAppear { if !loaded { loadInitial(); loaded = true } }
    }

    /// Pre-fills the form from `initial` (for editing an existing card): scalars, and table inputs whose
    /// initial is an array of `{column: value}` objects.
    private func loadInitial() {
        guard let initial = asDict(d["initial"]) else { return }
        func scalar(_ f: [String: Any]) {
            let k = str(f, "key") ?? ""
            if let v = initial[k], !(v is NSNull) { values[k] = "\(v)" }
        }
        for input in inputs {
            switch str(input, "type") ?? "" {
            case "table":
                let key = str(input, "key") ?? ""
                let cols = asArray(input["columns"]).compactMap { asDict($0) }
                let rows = asArray(initial[key]).compactMap { asDict($0) }
                if !rows.isEmpty {
                    tables[key] = rows.map { r in cols.map { c in
                        let v = r[str(c, "key") ?? ""]; return (v == nil || v is NSNull) ? "" : "\(v!)"
                    } }
                }
            case "photos":
                let key = str(input, "key") ?? ""
                let paths = asArray(initial[key]).map { "\($0)" }
                if !paths.isEmpty { photos[key] = paths }
            case "row":
                asArray(input["fields"]).compactMap { asDict($0) }.forEach(scalar)
            default:
                scalar(input)
            }
        }
    }

    /// Combines scalar fields, table inputs, and any static `with` fields into the handler payload.
    /// Table data arrives as an array of `{column: value}` objects (the same shape micro-tool tables use).
    private func payload() -> [String: Any] {
        var out: [String: Any] = values
        for input in inputs where str(input, "type") == "table" {
            let key = str(input, "key") ?? ""
            let cols = asArray(input["columns"]).compactMap { asDict($0) }
            let rows = tables[key] ?? []
            out[key] = rows.map { row -> [String: String] in
                var obj: [String: String] = [:]
                for (i, c) in cols.enumerated() { obj[str(c, "key") ?? "col\(i)"] = i < row.count ? row[i] : "" }
                return obj
            }
        }
        for input in inputs where str(input, "type") == "photos" {
            out[str(input, "key") ?? ""] = photos[str(input, "key") ?? ""] ?? []
        }
        if let withD = asDict(d["with"]) { for (k, v) in withD { out[k] = v } }
        return out
    }

    @ViewBuilder private func inputRow(_ input: [String: Any]) -> some View {
        if str(input, "type") == "row" {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(asArray(input["fields"]).compactMap { asDict($0) }.enumerated()), id: \.offset) { _, f in
                    field(f)
                }
            }
        } else if str(input, "type") == "table" {
            tableInput(input)
        } else if str(input, "type") == "photos" {
            let key = str(input, "key") ?? ""
            VStack(alignment: .leading, spacing: 4) {
                Text((str(input, "label") ?? "Photos").uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                NodePhotoInput(folder: ctx.baseURL,
                               paths: Binding(get: { photos[key] ?? [] }, set: { photos[key] = $0 }))
            }
        } else {
            field(input)
        }
    }

    /// An editable table input: named columns, add/remove rows, cell text fields.
    @ViewBuilder private func tableInput(_ input: [String: Any]) -> some View {
        let key = str(input, "key") ?? ""
        let label = str(input, "label") ?? key
        let cols = asArray(input["columns"]).compactMap { asDict($0) }
        let rows = tables[key] ?? []
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(Array(cols.enumerated()), id: \.offset) { _, c in
                        Text(str(c, "label") ?? "").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(width: 22)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { r, _ in
                    HStack(spacing: 8) {
                        ForEach(Array(cols.enumerated()), id: \.offset) { cIdx, c in
                            TextField(str(c, "numeric") as? Bool == true ? "0" : "",
                                      text: cellBinding(key, r, cIdx, colCount: cols.count))
                                .textFieldStyle(.plain).font(.callout)
                                .padding(6).background(fieldBg())
                                .frame(maxWidth: .infinity)
                        }
                        Button { removeRow(key, r) } label: {
                            Image(systemName: "minus.circle").font(.callout).foregroundStyle(.tertiary)
                        }.buttonStyle(.plain).frame(width: 22)
                    }
                }
                Button { addRow(key, cols.count) } label: {
                    Label(str(input, "addLabel") ?? "Add row", systemImage: "plus")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
            .padding(8).background(fieldBg())
        }
    }

    private func cellBinding(_ key: String, _ row: Int, _ col: Int, colCount: Int) -> Binding<String> {
        Binding(
            get: { let rows = tables[key] ?? []; return row < rows.count && col < rows[row].count ? rows[row][col] : "" },
            set: { newValue in
                var rows = tables[key] ?? []
                while rows.count <= row { rows.append(Array(repeating: "", count: colCount)) }
                while rows[row].count < colCount { rows[row].append("") }
                rows[row][col] = newValue
                tables[key] = rows
            })
    }
    private func addRow(_ key: String, _ colCount: Int) {
        tables[key, default: []].append(Array(repeating: "", count: colCount))
    }
    private func removeRow(_ key: String, _ row: Int) {
        guard var rows = tables[key], row < rows.count else { return }
        rows.remove(at: row); tables[key] = rows
    }

    @ViewBuilder private func field(_ f: [String: Any]) -> some View {
        let key = str(f, "key") ?? ""
        let label = str(f, "label") ?? key
        let placeholder = str(f, "placeholder") ?? ""
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            switch str(f, "type") ?? "text" {
            case "textarea":
                TextField(placeholder, text: binding(key), axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.plain).font(.callout)
                    .padding(8).background(fieldBg())
            case "picker":
                pickerField(f, key)
            default:
                TextField(placeholder, text: binding(key))
                    .textFieldStyle(.plain).font(.callout)
                    .padding(8).background(fieldBg())
            }
        }
    }

    /// A selector: a row of chips (segmented) for a handful of options, choosing one value.
    private func pickerField(_ f: [String: Any], _ key: String) -> some View {
        let options = asArray(f["options"]).compactMap { asDict($0) }
        let current = values[key] ?? ""
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                    let value = str(opt, "value") ?? ""
                    let on = current == value
                    Button { values[key] = value } label: {
                        Text(str(opt, "label") ?? value).font(.callout.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(on ? 0.2 : 0.06)))
                            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(on ? 0.6 : 0), lineWidth: 1))
                            .foregroundStyle(on ? .primary : .secondary)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }
    private func fieldBg() -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
    }
}

// MARK: - Photo input (paste or import → saved into the card's folder `_assets/`)

private struct NodePhotoInput: View {
    let folder: URL?
    @Binding var paths: [String]
    @Environment(NidusModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(paths.enumerated()), id: \.offset) { idx, rel in
                    thumbnail(rel, idx)
                }
                addTile
            }
        }
    }

    @ViewBuilder private func thumbnail(_ rel: String, _ idx: Int) -> some View {
        if let folder, let img = nidusLoadImage(at: folder.appendingPathComponent(rel)) {
            img.resizable().scaledToFill().frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button { paths.remove(at: idx) } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.white, .black.opacity(0.5))
                    }.buttonStyle(.plain).padding(3)
                }
        }
    }

    private var addTile: some View {
        Button(action: importPhotos) {
            Image(systemName: "plus").font(.title3).foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])))
        }
        .buttonStyle(.plain)
        .focusable().focusEffectDisabled().focused($focused)
        .onHover { focused = $0 }
        #if os(macOS)
        .onPasteCommand(of: [.image, .fileURL]) { _ in pastePhoto() }
        #endif
        .help("Add a photo — click to import, or hover + ⌘V to paste")
    }

    private func pastePhoto() {
        guard let folder else { return }
        if let png = ReferenceStore.clipboardImagePNG(), let rel = model.saveCardImage(png, ext: "png", intoProjectFolder: folder) {
            paths.append(rel)
        } else {
            for url in ReferenceStore.clipboardImageURLs() {
                if let rel = model.importCardImage(from: url, intoProjectFolder: folder) { paths.append(rel) }
            }
        }
    }

    private func importPhotos() {
        guard let folder else { return }
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { resp in
            guard resp == .OK else { return }
            for url in panel.urls { if let rel = model.importCardImage(from: url, intoProjectFolder: folder) { paths.append(rel) } }
        }
        #endif
    }
}

// MARK: - The board tile

struct InstalledToolTileView: View {
    let tool: InstalledTool
    let context: ToolContext

    @Environment(NidusModel.self) private var model
    @Environment(WorkspaceOverlay.self) private var overlay
    @Environment(CardDragController.self) private var drag
    @State private var localRefresh = 0

    private var primaryFile: URL? {
        guard let store = tool.manifest.store.first else { return nil }
        return context.fileURL(store)
    }
    /// Heuristic: does the tool define an expanded view worth opening on a tile tap?
    private var hasExpanded: Bool { tool.source.contains("expanded") }
    /// A shareable tool is a drop target — a card dropped on it is moved into its store (bidirectional
    /// with Inbox/Ideas/Tasks). Silos (shareable:false) don't accept drops.
    private var acceptsDrops: Bool { tool.manifest.shareable }

    private var run: InstalledToolEngine.Run {
        InstalledToolEngine.Run(tool: tool, primaryFile: primaryFile, size: context.size.rawValue,
                                vaultURL: model.vaultURL, onOpenCard: openCard, onOpenExpanded: openExpanded)
    }

    var body: some View {
        let node = InstalledToolEngine.render("tile", run)
        VStack(spacing: 6) {
            ZStack {
                // Background tap opens the expanded view; interactive nodes (buttons/forms) consume theirs.
                if hasExpanded {
                    Color.clear.contentShape(Rectangle()).onTapGesture { openExpanded() }
                }
                TidyScroll {
                    NodeView(node: node, ctx: nodeCtx)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A pinned footer (doesn't scroll) that opens the expanded library — like Notebook.
            if hasExpanded {
                Button { openExpanded() } label: {
                    HStack(spacing: 4) {
                        Text(tool.manifest.openLabel ?? "Open \(tool.manifest.name)").font(.caption.weight(.medium))
                        Image(systemName: "arrow.right").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .id("\(model.fileChangeTick)-\(localRefresh)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Accept dropped cards (shareable tools) — same mechanism the built-in tools use.
        .overlay {
            if acceptsDrops {
                CardDropHighlight(active: primaryFile != nil && drag.targetFile?.standardizedFileURL == primaryFile?.standardizedFileURL)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ToolFramePreferenceKey.self,
                    value: acceptsDrops ? [ToolFrameInfo(fileURL: primaryFile, toolID: tool.id,
                                                         frame: geo.frame(in: .named("workspace")))] : [])
            }
        )
    }

    private var nodeCtx: NodeContext {
        NodeContext(run: run, baseURL: context.folderURL) { name, payload in
            InstalledToolEngine.runHandler(name, payload: payload, run)
            model.notifyFileChange()
            localRefresh &+= 1
        }
    }

    private func openExpanded() {
        let t = tool, file = primaryFile, folder = context.folderURL, size = context.size.rawValue
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                InstalledToolExpandedView(tool: t, primaryFile: file, folderURL: folder, size: size) {
                    withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                }
            }
        }
    }

    private func openCard(_ id: String) {
        guard let file = primaryFile, let card = CardStore.read(from: file).first(where: { $0.id == id }) else { return }
        let t = tool, folder = context.folderURL, size = context.size.rawValue
        withAnimation(.easeOut(duration: 0.2)) {
            overlay.present {
                // If the tool defines a custom `card` detail, show its structured view (Glazy-style:
                // badges, recipe table, gallery). Otherwise fall back to the app's native card editor.
                if InstalledToolEngine.defines(t, "card") {
                    InstalledToolCardPanel(tool: t, cardID: id, primaryFile: file, folderURL: folder, size: size) {
                        withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                    }
                } else {
                    CardDetailView(card: card, fileURL: file, folderURL: folder,
                                   toolIcon: t.manifest.icon, toolName: t.manifest.name) {
                        withAnimation(.easeOut(duration: 0.18)) { overlay.dismiss() }
                    }
                }
            }
        }
    }
}

// MARK: - Expanded view (a panel running the tool's `expanded`)

struct InstalledToolExpandedView: View {
    let tool: InstalledTool
    let primaryFile: URL?
    let folderURL: URL?
    let size: String
    let onClose: () -> Void

    @Environment(NidusModel.self) private var model
    @State private var localRefresh = 0
    @State private var openCardID: String?
    @State private var measuredContent: CGFloat = 0   // natural height of the rendered tree

    private let panelWidth: CGFloat = 900
    private let headerChrome: CGFloat = 55             // header row + divider
    private let minPanelHeight: CGFloat = 360

    private var run: InstalledToolEngine.Run {
        InstalledToolEngine.Run(tool: tool, primaryFile: primaryFile, size: size,
                                vaultURL: model.vaultURL, onOpenCard: { openCardID = $0 })
    }

    var body: some View {
        // A tool's expanded panel sizes to its CONTENT so it doesn't force a scroll — capped only by the
        // window (see the "size to content" rule in the toolmaker skill). If content exceeds the cap,
        // TidyScroll still scrolls the overflow.
        GeometryReader { proxy in
            let node = InstalledToolEngine.render("expanded", run)
            let width = min(panelWidth, proxy.size.width - 48)
            let maxH = max(minPanelHeight, proxy.size.height - 48)
            let height = min(max(measuredContent + headerChrome, minPanelHeight), maxH)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: tool.manifest.icon).font(.title3).foregroundStyle(.secondary)
                    Text(tool.manifest.name).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    NotebookCircleButton(system: "xmark", action: onClose)
                }
                .padding(.horizontal, 22).padding(.vertical, 14)
                Divider().opacity(0.4)
                TidyScroll {
                    NodeView(node: node, ctx: nodeCtx)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
            .frame(width: width, height: height)
            .glassCard()
            .background(Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0))
            // Off-screen measurer: reports the tree's natural height (unconstrained) so the panel can grow.
            .background(
                NodeView(node: node, ctx: nodeCtx)
                    .frame(width: width - 40, alignment: .leading)
                    .padding(20)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredContent = $0 }
                    .hidden().allowsHitTesting(false)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // centre in the window
        }
        .id("\(model.fileChangeTick)-\(localRefresh)")
        .overlay { cardOverlay }
        .animation(.easeOut(duration: 0.16), value: measuredContent)
    }

    @ViewBuilder private var cardOverlay: some View {
        if let id = openCardID, let file = primaryFile,
           let card = CardStore.read(from: file).first(where: { $0.id == id }) {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).frame(width: 5000, height: 5000)
                    .onTapGesture { openCardID = nil }
                if InstalledToolEngine.defines(tool, "card") {
                    InstalledToolCardPanel(tool: tool, cardID: id, primaryFile: file,
                                           folderURL: folderURL, size: size) { openCardID = nil }
                } else {
                    CardDetailView(card: card, fileURL: file, folderURL: folderURL,
                                   toolIcon: tool.manifest.icon, toolName: tool.manifest.name) { openCardID = nil }
                }
            }
            .transition(.opacity)
        }
    }

    private var nodeCtx: NodeContext {
        NodeContext(run: run, baseURL: folderURL) { name, payload in
            InstalledToolEngine.runHandler(name, payload: payload, run)
            model.notifyFileChange()
            localRefresh &+= 1
        }
    }
}

// MARK: - Card detail (structured — runs the tool's own `card` render)

struct InstalledToolCardPanel: View {
    let tool: InstalledTool
    let cardID: String
    let primaryFile: URL?
    let folderURL: URL?
    let size: String
    let onClose: () -> Void

    @Environment(NidusModel.self) private var model
    @State private var localRefresh = 0
    @State private var editing = false
    @State private var measuredContent: CGFloat = 0

    private let panelWidth: CGFloat = 640
    private let headerChrome: CGFloat = 55
    private let minPanelHeight: CGFloat = 300

    private var run: InstalledToolEngine.Run {
        InstalledToolEngine.Run(tool: tool, primaryFile: primaryFile, size: size, vaultURL: model.vaultURL)
    }
    private var cardDict: [String: Any]? {
        guard let file = primaryFile else { return nil }
        return CardStore.read(from: file).first { $0.id == cardID }.map(InstalledToolEngine.cardToDict)
    }
    private var canEdit: Bool { InstalledToolEngine.defines(tool, "edit") }

    private var panelCtx: NodeContext {
        NodeContext(run: run, baseURL: folderURL) { name, payload in
            InstalledToolEngine.runHandler(name, payload: payload, run)
            model.notifyFileChange()
            withAnimation(.easeInOut(duration: 0.15)) { editing = false }   // a save returns to the read view
            localRefresh &+= 1
        }
    }

    var body: some View {
        // Sizes to its content so a glaze's recipe/form isn't trapped behind a scroll — capped by the
        // window (the "size to content" rule; see the toolmaker skill).
        GeometryReader { proxy in
            let node = InstalledToolEngine.render(editing ? "edit" : "card", run, card: cardDict)
            let width = min(panelWidth, proxy.size.width - 48)
            let maxH = max(minPanelHeight, proxy.size.height - 48)
            let height = min(max(measuredContent + headerChrome, minPanelHeight), maxH)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: tool.manifest.icon).font(.title3).foregroundStyle(.secondary)
                    Text(tool.manifest.name).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if canEdit {
                        if editing {
                            // NOT a checkmark: leaving edit does NOT save (Save is the button below). Make
                            // that explicit so it never feels like a deceptive "OK / confirm".
                            Button { withAnimation(.easeInOut(duration: 0.15)) { editing = false } } label: {
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text("Leave editing").font(.caption.weight(.medium))
                                    Text("doesn't save").font(.system(size: 9)).foregroundStyle(.tertiary)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Return to the read view. Use “Save changes” below to keep your edits.")
                        } else {
                            NotebookCircleButton(system: "pencil") {
                                withAnimation(.easeInOut(duration: 0.15)) { editing = true }
                            }
                        }
                    }
                    NotebookCircleButton(system: "xmark", action: onClose)
                }
                .padding(.horizontal, 22).padding(.vertical, 14)
                Divider().opacity(0.4)
                TidyScroll {
                    NodeView(node: node, ctx: panelCtx)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            }
            .frame(width: width, height: height)
            .glassCard()
            .background(Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0))
            .background(
                NodeView(node: node, ctx: panelCtx)
                    .frame(width: width - 48, alignment: .leading)
                    .padding(24)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredContent = $0 }
                    .hidden().allowsHitTesting(false)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id("\(model.fileChangeTick)-\(localRefresh)")
        .animation(.easeOut(duration: 0.16), value: measuredContent)
    }
}
