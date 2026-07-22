//
//  NotebookNoteEditor.swift
//  Nidus
//
//  The note editor, shown full-bleed inside the Notebook library. A big title, an outline drawn from
//  the note's own headings, the Markdown body, and an info/tools column (info + micro-tools + delete).
//  The body autosaves; the frontmatter (id/created) stays hidden — the user only ever sees their words.
//
//  Notes open RENDERED (via MarkdownView, which understands headings/lists/tables/code/images/basic
//  HTML); the pencil flips to raw-Markdown editing with the formatting toolbar. The .md is always the
//  source of truth.
//

import SwiftUI
import UniformTypeIdentifiers

struct NotebookNoteEditor: View {
    let item: NotebookStore.Item?      // nil → a brand-new note (created on first content)
    let newZone: String?               // where a new note is created
    let projectFolder: URL?
    // Micro-tools live in this editor's info column; the runner floats window-wide from the library.
    let microTools: [MicroTool]
    let onRunTool: (MicroTool) -> Void
    let onManageTools: () -> Void
    let onBack: () -> Void

    @Environment(NidusModel.self) private var model

    @State private var current: NotebookStore.Item?
    @State private var title = ""
    @State private var body_ = ""
    @State private var bodySelection: TextSelection?
    @State private var selectedHeadingID: Int?
    @State private var created: String = ""
    @State private var saved = true
    @State private var saveToken = 0
    @State private var didLoad = false     // suppress the autosave that assigning title/body on load fires
    @State private var dirty = false        // real edits happened → worth writing on the way out
    @State private var editing = false      // false = rendered read view; true = raw Markdown + toolbar
    @State private var scrollTarget: Int?   // rendered mode: block index to scroll the outline to

    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                outlineColumn.frame(width: 210)
                Divider().opacity(0.4)
                editorColumn.frame(maxWidth: .infinity)
                Divider().opacity(0.4)
                infoColumn.frame(width: 172)   // thinner — it holds little; the notes get the room
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: flushSave)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            NotebookCircleButton(system: "chevron.left") { flushSave(); onBack() }
            if editing {
                TextField("Untitled", text: $title)
                    .textFieldStyle(.plain).font(.title2.weight(.bold))
                    .focused($titleFocused)
                    .onSubmit { titleFocused = false; scheduleSave() }
                    .onChange(of: title) { scheduleSave() }
            } else {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(title.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
            }
            if editing { Text(saved ? "Saved" : "Saving…").font(.caption).foregroundStyle(.tertiary) }
            Spacer(minLength: 8)
            // Rendered by default; the pencil flips to raw-Markdown editing (the .md is always the truth).
            NotebookCircleButton(system: editing ? "checkmark" : "pencil") {
                withAnimation(.easeInOut(duration: 0.18)) { editing.toggle() }
            }
            NotebookCircleButton(system: "xmark") { flushSave(); onBack() }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .onChange(of: titleFocused) { _, f in model.isEditingText = f }
    }

    // MARK: Outline

    private var outlineColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Outline").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            let heads = headings
            if heads.isEmpty {
                Text("Headings you add appear here as a clickable index.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                TidyScroll {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(heads) { h in outlineRow(h) }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 16)
                }
            }
        }
    }

    private func outlineRow(_ h: Heading) -> some View {
        let selected = selectedHeadingID == h.id
        return Button { jump(to: h) } label: {
            Text(h.text)
                .font(h.level <= 1 ? .callout.weight(.medium) : .caption)
                .foregroundStyle(selected ? Color.accentColor : (h.level <= 1 ? .primary : .secondary))
                .lineLimit(1)
                .padding(.leading, 8 + CGFloat(max(0, h.level - 1)) * 14)
                .padding(.trailing, 8).padding(.vertical, h.level <= 1 ? 6 : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(selected ? 0.10 : 0)))
                .overlay(alignment: .leading) {
                    if selected {
                        RoundedRectangle(cornerRadius: 2).fill(Color.accentColor)
                            .frame(width: 2.5, height: 14).padding(.leading, 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Clicking an outline entry: in edit mode it drops the caret at that heading (the editor scrolls
    /// to the caret); in rendered mode it scrolls the rendered view to that heading's block.
    private func jump(to h: Heading) {
        selectedHeadingID = h.id
        if editing {
            bodySelection = TextSelection(insertionPoint: h.index)
        } else if let blockIndex = headingBlockIndices[safe: h.ordinal] {
            scrollTarget = blockIndex
        }
    }

    /// Block indices (into `MarkdownParser.parse(body_)`) that are headings, in document order — so the
    /// k-th outline heading maps to `headingBlockIndices[k]` for scroll-to in rendered mode.
    private var headingBlockIndices: [Int] {
        MarkdownParser.parse(body_).enumerated().compactMap { i, block in
            if case .heading = block { return i } else { return nil }
        }
    }

    // `id` is the heading's character offset from the start — stable across the recomputations that
    // editing triggers (a fresh UUID each time would break ForEach identity and the selection).
    private struct Heading: Identifiable { let id: Int; let ordinal: Int; let level: Int; let text: String; let index: String.Index }
    private var headings: [Heading] {
        var result: [Heading] = []
        var lineStart = body_.startIndex
        var ordinal = 0
        for rawLine in body_.components(separatedBy: "\n") {
            let t = rawLine.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") {
                let hashes = t.prefix { $0 == "#" }.count
                let text = t.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                if hashes >= 1, hashes <= 6, !text.isEmpty {
                    let offset = body_.distance(from: body_.startIndex, to: lineStart)
                    result.append(Heading(id: offset, ordinal: ordinal, level: hashes, text: text, index: lineStart))
                    ordinal += 1
                }
            }
            // Advance to the next line start (past this line's characters and the "\n").
            let afterLine = body_.index(lineStart, offsetBy: rawLine.count, limitedBy: body_.endIndex) ?? body_.endIndex
            lineStart = afterLine < body_.endIndex ? body_.index(after: afterLine) : body_.endIndex
        }
        return result
    }

    // MARK: Editor

    @ViewBuilder private var editorColumn: some View {
        if editing { rawEditor } else { renderedView }
    }

    /// Raw Markdown editing with the formatting toolbar (the .md is always the source of truth).
    private var rawEditor: some View {
        VStack(spacing: 0) {
            NotebookMDToolbar(
                bold: { wrapSelection("**") }, italic: { wrapSelection("*") },
                title: { applyLinePrefix("# ") }, heading: { applyLinePrefix("## ") },
                bullet: { applyLinePrefix("- ") }, numbered: { applyLinePrefix("1. ") },
                table: { insertTable() }, link: { insertLink() }, image: { insertImage() },
                alignLeft: { wrapAlign("left") }, alignCenter: { wrapAlign("center") },
                alignRight: { wrapAlign("right") })
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)
            Divider().opacity(0.3)
            TextEditor(text: $body_, selection: $bodySelection)
                .font(.system(.body))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .onChange(of: body_) { scheduleSave() }
                // Paste an image: save it into the note's folder and drop a Markdown ref at the caret.
                // (Select that line + Align to center it — the renderer honours the alignment.)
                .pasteImageIntoNote { pasteImage() }
        }
        .overlay(alignment: .bottomLeading) {
            Text("\(wordCount) words").font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 22).padding(.bottom, 8)
        }
    }

    /// Rendered read view — the note as real Markdown (headings big, bold bold, lists/tables/code),
    /// via the renderer the rest of the app uses. Double-clicking anywhere jumps into edit mode.
    private var renderedView: some View {
        let blocks = MarkdownParser.parse(body_)
        return ScrollViewReader { proxy in
            TidyScroll {
                Group {
                    if body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Empty note. Click the pencil to write.")
                            .font(.callout).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                                MarkdownView(blocks: [block], baseURL: current?.url.deletingLastPathComponent())
                                    .id("block-\(i)")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26).padding(.vertical, 20)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("block-\(target)", anchor: .top) }
                scrollTarget = nil
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { withAnimation(.easeInOut(duration: 0.18)) { editing = true } }
    }

    private var wordCount: Int {
        body_.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    // MARK: Info

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INFORMATION").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            infoRow("Type", "Markdown")
            if let c = createdDisplay { infoRow("Created", c) }
            if let e = editedDisplay { infoRow("Edited", e) }

            Divider().opacity(0.3).padding(.horizontal, 14).padding(.vertical, 12)
            toolsSection

            Spacer(minLength: 12)
            Divider().opacity(0.3).padding(.horizontal, 14)
            Button(role: .destructive) { deleteNote() } label: {
                Label("Delete", systemImage: "trash").font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            }.buttonStyle(.plain)
        }
    }

    /// Micro-tools list — moved here (the user's call) so they sit in the note's own column. Each runs
    /// its tool (output copies to the clipboard, then ⌘V into the note); "+" manages/imports.
    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TOOLS").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.tertiary)
                Spacer()
                Button(action: onManageTools) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .contentShape(Circle())
                }.buttonStyle(.plain).help("Manage / import micro-tools")
            }
            .padding(.horizontal, 12).padding(.bottom, 2)
            ForEach(microTools) { tool in NotebookToolPill(tool: tool) { onRunTool(tool) } }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
    }

    private var createdDisplay: String? {
        guard !created.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        guard let d = iso.date(from: created) else { return nil }
        return Self.medium.string(from: d)
    }
    private var editedDisplay: String? {
        current.map { NotebookIcon.relativeEdited($0.modified) }
    }
    private static let medium: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; return f }()

    // MARK: Load / save

    private func load() {
        current = item
        if let item {
            title = item.title
            body_ = NotebookStore.readBody(item)
            if let text = try? String(contentsOf: item.url, encoding: .utf8) {
                created = NotebookStore.parseFrontmatter(text).meta["created"] ?? ""
            }
        }
        // A brand-new note opens straight in edit mode; an existing note opens rendered.
        editing = (item == nil)
        // Only accept edits AFTER the initial title/body assignments above (whose onChange would
        // otherwise fire a spurious save, bumping mtime so every open looked like an edit).
        DispatchQueue.main.async {
            didLoad = true
            if item == nil { titleFocused = true }   // a brand-new note starts ready to name
        }
    }

    private var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scheduleSave() {
        guard didLoad else { return }
        dirty = true
        saved = false
        let token = saveToken &+ 1
        saveToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if saveToken == token { commitSave(rename: false) }
        }
    }

    private func flushSave() {
        model.isEditingText = false
        if dirty { commitSave(rename: true) }   // settle the filename to the final title on the way out
    }

    private func commitSave(rename: Bool) {
        guard hasContent else { saved = true; return }
        if let cur = current {
            if let updated = NotebookStore.updateNote(cur, title: title, body: body_,
                                                      renameToMatchTitle: rename, projectFolder: projectFolder) {
                current = updated
            }
        } else if let createdItem = NotebookStore.createNote(
                    title: title.isEmpty ? "Untitled" : title, body: body_,
                    in: newZone ?? "", projectFolder: projectFolder) {
            current = createdItem
            if let text = try? String(contentsOf: createdItem.url, encoding: .utf8) {
                created = NotebookStore.parseFrontmatter(text).meta["created"] ?? ""
            }
        }
        saved = true
        model.notifyFileChange()
    }

    private func deleteNote() {
        if let cur = current { NotebookStore.delete(cur, projectFolder: projectFolder) }
        model.notifyFileChange()
        onBack()
    }

    // MARK: Markdown toolbar actions (operate on the caret/selection in the body)

    private func selectedRange() -> Range<String.Index> {
        switch bodySelection?.indices {
        case .selection(let r): return r
        case .multiSelection(let set): return set.ranges.first ?? body_.endIndex..<body_.endIndex
        case .none: return body_.endIndex..<body_.endIndex
        @unknown default: return body_.endIndex..<body_.endIndex
        }
    }

    /// Bold/Italic: wraps the selection, or drops an empty pair with the caret between when nothing's selected.
    private func wrapSelection(_ marker: String) {
        let r = selectedRange()
        if r.isEmpty {
            body_.insert(contentsOf: marker + marker, at: r.lowerBound)
            let mid = body_.index(r.lowerBound, offsetBy: marker.count)
            bodySelection = TextSelection(insertionPoint: mid)
        } else {
            let start = r.lowerBound
            let replacement = marker + body_[r] + marker
            body_.replaceSubrange(r, with: replacement)
            let end = body_.index(start, offsetBy: replacement.count)
            bodySelection = TextSelection(range: start..<end)
        }
    }

    /// Heading/bullet/numbered: prefixes EVERY line touched by the selection (so a multi-line
    /// selection turns each line into a list item), or just the caret's line when nothing's selected.
    private func applyLinePrefix(_ prefix: String) {
        let r = selectedRange()
        let lineSpan = body_.lineRange(for: r.lowerBound..<r.upperBound)
        let selected = String(body_[lineSpan])
        let prefixed = selected
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? String($0) : prefix + $0 }
            .joined(separator: "\n")
        body_.replaceSubrange(lineSpan, with: prefixed)
        let newEnd = body_.index(lineSpan.lowerBound, offsetBy: prefixed.count)
        bodySelection = TextSelection(range: lineSpan.lowerBound..<newEnd)
    }

    /// Inserts a ready-to-fill 2×2 table at the caret, on its own paragraph.
    private func insertTable() {
        let caret = selectedRange().lowerBound
        let needsBreak = caret != body_.startIndex && body_[body_.index(before: caret)] != "\n"
        let template = (needsBreak ? "\n\n" : "") + "| Header | Header |\n| --- | --- |\n| Cell | Cell |\n"
        body_.insert(contentsOf: template, at: caret)
        bodySelection = TextSelection(insertionPoint: body_.index(caret, offsetBy: template.count))
    }

    /// Link: wraps the selection as `[selection](url)` with the caret ready in the URL, or inserts a
    /// `[text](url)` template when nothing is selected.
    private func insertLink() {
        let r = selectedRange()
        let label = r.isEmpty ? "text" : String(body_[r])
        let replacement = "[\(label)](url)"
        body_.replaceSubrange(r, with: replacement)
        // Put the caret on "url" so it's the first thing you overwrite.
        let urlStart = body_.index(r.lowerBound, offsetBy: label.count + 3)  // "[" + label + "]("
        bodySelection = TextSelection(range: urlStart..<body_.index(urlStart, offsetBy: 3))
    }

    /// Image: inserts a `![alt](url)` template on its own paragraph.
    private func insertImage() {
        let caret = selectedRange().lowerBound
        let needsBreak = caret != body_.startIndex && body_[body_.index(before: caret)] != "\n"
        let template = (needsBreak ? "\n\n" : "") + "![alt](url)\n"
        body_.insert(contentsOf: template, at: caret)
        bodySelection = TextSelection(insertionPoint: body_.index(caret, offsetBy: template.count))
    }

    /// Saves whatever image is on the clipboard into the note's `_assets/` and inserts a Markdown
    /// image reference at the caret (on its own paragraph). The rendered view resolves it via baseURL.
    private func pasteImage() {
        guard let folder = noteFolder else { return }
        var rel: String?
        if let png = ReferenceStore.clipboardImagePNG() {
            rel = model.saveCardImage(png, ext: "png", intoProjectFolder: folder)
        } else if let url = ReferenceStore.clipboardImageURLs().first {
            rel = model.importCardImage(from: url, intoProjectFolder: folder)
        }
        guard let rel else { return }
        let caret = selectedRange().lowerBound
        let needsBreak = caret != body_.startIndex && body_[body_.index(before: caret)] != "\n"
        let snippet = (needsBreak ? "\n\n" : "") + "![](\(rel))\n"
        body_.insert(contentsOf: snippet, at: caret)
        bodySelection = TextSelection(insertionPoint: body_.index(caret, offsetBy: snippet.count))
    }

    /// The folder the note lives in (its `_assets/` gets the pasted images). Works for a new note too.
    private var noteFolder: URL? {
        current?.url.deletingLastPathComponent()
            ?? NotebookStore.zoneURL(newZone ?? "", projectFolder: projectFolder)
    }

    /// Wraps the selected block(s) in `<div align="…"> … </div>` — the renderer honours the alignment.
    private func wrapAlign(_ align: String) {
        let r = selectedRange()
        let span = body_.lineRange(for: r.lowerBound..<r.upperBound)
        var content = String(body_[span])
        if content.hasSuffix("\n") { content.removeLast() }
        let wrapped = "<div align=\"\(align)\">\n\(content)\n</div>\n"
        body_.replaceSubrange(span, with: wrapped)
        let end = body_.index(span.lowerBound, offsetBy: wrapped.count)
        bodySelection = TextSelection(insertionPoint: end)
    }
}

// MARK: - Tool pill (a micro-tool in the info column)

private struct NotebookToolPill: View {
    let tool: MicroTool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tool.icon).font(.callout).foregroundStyle(hover ? Color.accentColor : .secondary)
                    .frame(width: 20)
                Text(tool.name).font(.callout).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.09 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(hover ? 0.14 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .padding(.horizontal, 10)
        .help("Run \(tool.name) — output copies to the clipboard")
    }
}

// MARK: - Markdown toolbar

private struct NotebookMDToolbar: View {
    let bold: () -> Void
    let italic: () -> Void
    let title: () -> Void
    let heading: () -> Void
    let bullet: () -> Void
    let numbered: () -> Void
    let table: () -> Void
    let link: () -> Void
    let image: () -> Void
    let alignLeft: () -> Void
    let alignCenter: () -> Void
    let alignRight: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            button("bold", "Bold", bold)
            button("italic", "Italic", italic)
            Divider().frame(height: 14).opacity(0.4)
            textButton("H1", "Title (#)", title)
            textButton("H2", "Heading (##)", heading)
            button("list.bullet", "Bullet list", bullet)
            button("list.number", "Numbered list", numbered)
            Divider().frame(height: 14).opacity(0.4)
            button("link", "Link", link)
            button("photo", "Image", image)
            button("tablecells", "Table", table)
            Divider().frame(height: 14).opacity(0.4)
            button("text.alignleft", "Align left", alignLeft)
            button("text.aligncenter", "Align center", alignCenter)
            button("text.alignright", "Align right", alignRight)
            Spacer(minLength: 0)
        }
    }

    private func button(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        MDToolButton(systemName: symbol, help: help, action: action)
    }

    private func textButton(_ text: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        MDToolButton(text: text, help: help, action: action)
    }

    private struct MDToolButton: View {
        var systemName: String? = nil
        var text: String? = nil
        var help: String = ""
        let action: () -> Void
        @State private var hover = false
        var body: some View {
            Button(action: action) {
                Group {
                    if let systemName {
                        Image(systemName: systemName).font(.system(size: 12, weight: .medium))
                    } else {
                        Text(text ?? "").font(.system(size: 11, weight: .bold))
                    }
                }
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hover ? 0.10 : 0)))
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help(help)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension View {
    /// Fires `action` on a ⌘V paste of an image or image file (macOS). Text pastes are unaffected.
    @ViewBuilder func pasteImageIntoNote(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onPasteCommand(of: [.image, .fileURL]) { _ in action() }
        #else
        self
        #endif
    }
}
