//
//  MarkdownRender.swift
//  Nidus
//
//  A small, purpose-built Markdown renderer for card notes: headings, bold/italic, bullet/numbered
//  lists and GFM-style pipe tables. No third-party dependency — Nidus stays self-contained — and it
//  lets the visual style match the app's own flat/glass language instead of a library's look.
//  Inline emphasis (bold/italic/code) is delegated to `AttributedString(markdown:)` per line/cell,
//  which already understands that subset perfectly well; this file only adds the BLOCK structure
//  (headings/lists/tables) that the native initializer doesn't parse.
//

import SwiftUI
import CryptoKit

enum MDBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([String])
    case numberedList([String])
    case table(headers: [String], rows: [[String]])
    case code(String)          // ``` fenced block — monospace, whitespace preserved (ASCII art, etc.)
    case image(src: String, alt: String)   // Markdown ![alt](src) or an HTML <img> — rendered inline
    indirect case aligned(MDAlign, [MDBlock])   // <div align="center|left|right"> … </div>
}

/// Horizontal alignment from an HTML `align` attribute.
enum MDAlign: String, Equatable { case leading, center, trailing
    var hStack: HorizontalAlignment { self == .center ? .center : (self == .trailing ? .trailing : .leading) }
    var frame: Alignment { self == .center ? .center : (self == .trailing ? .trailing : .leading) }
    init(html: String) {
        switch html.lowercased() {
        case "center": self = .center
        case "right", "end": self = .trailing
        default: self = .leading
        }
    }
}

enum MarkdownParser {

    /// A flattened, symbol-free version of Markdown for compact previews (card rows, etc.): the same
    /// text with the *noise* removed — heading `#`, table pipes, emphasis `*_`` `, list bullets, quote
    /// `>`, link/image syntax, HTML tags — so a note reads as plain prose instead of raw Markdown.
    /// It intentionally does NOT render structure (a card preview is one flat line); it only strips.
    static func plainPreview(_ text: String) -> String {
        var out: [String] = []
        var inFence = false
        for raw in text.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inFence.toggle(); continue }   // drop code-fence markers
            if inFence { out.append(line); continue }                 // keep fenced content as-is
            if line.isEmpty { continue }
            // Table separator rows (| --- | :--: |) carry no content — drop them.
            if line.range(of: "^\\|?[\\s:|-]+\\|?$", options: .regularExpression) != nil,
               line.contains("-") { continue }
            line = line.replacingOccurrences(of: "|", with: "  ")     // table cells → spaces
            // Leading block markers: heading #, quote >, list bullets, numbered list.
            line = line.replacingOccurrences(of: "^\\s*#{1,6}\\s*", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "^\\s*>\\s?", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "^\\s*[-*+]\\s+", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "^\\s*\\d+\\.\\s+", with: "", options: .regularExpression)
            // Images ![alt](url) → drop entirely; links [text](url) → keep just the text.
            line = line.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)   // HTML tags
            line = line.replacingOccurrences(of: "[*_`]", with: "", options: .regularExpression)      // inline emphasis/code
            line = line.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { out.append(line) }
        }
        return out.joined(separator: " ")
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ text: String) -> [MDBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MDBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { i += 1; continue }

            // Images: Markdown `![alt](src)` or an HTML `<img …>` on its own line → an image block.
            if let img = imageFrom(line) {
                blocks.append(.image(src: img.src, alt: img.alt))
                i += 1
                continue
            }
            // `<div align="center"> … </div>`: collect the wrapped region (matching nested divs) and
            // parse it recursively as an aligned group, so alignment actually renders.
            if let align = divAlignOpen(line) {
                var depth = 1
                var inner: [String] = []
                var j = i + 1
                while j < lines.count, depth > 0 {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if divAlignOpen(t) != nil || t.lowercased().hasPrefix("<div") { depth += 1 }
                    else if t.lowercased().hasPrefix("</div") { depth -= 1; if depth == 0 { break } }
                    if depth > 0 { inner.append(lines[j]) }
                    j += 1
                }
                blocks.append(.aligned(align, parse(inner.joined(separator: "\n"))))
                i = j + 1   // skip past the closing </div>
                continue
            }
            // Structural HTML wrappers on their own line (<div>, </div>, <p>, <br>, comments…) carry no
            // content our renderer shows — drop them so they don't appear as raw code (GitHub renders
            // inline HTML; our minimal renderer only understands images + Markdown blocks).
            if isStructuralHTMLLine(line) { i += 1; continue }

            // Fenced code block: keep the inner lines VERBATIM (indentation matters for ASCII art).
            if line.hasPrefix("```") {
                i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }   // consume the closing fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if let h = headingLevel(line) {
                blocks.append(.heading(level: h.level, text: h.text))
                i += 1
                continue
            }

            if isTableRow(line), i + 1 < lines.count, isSeparatorRow(lines[i + 1]) {
                let headers = splitRow(line)
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count, isTableRow(lines[j]) {
                    rows.append(splitRow(lines[j]))
                    j += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                i = j
                continue
            }

            if isBullet(line) {
                var items: [String] = []
                var j = i
                while j < lines.count, isBullet(lines[j].trimmingCharacters(in: .whitespaces)) {
                    items.append(bulletText(lines[j].trimmingCharacters(in: .whitespaces)))
                    j += 1
                }
                blocks.append(.bulletList(items))
                i = j
                continue
            }

            if numberedText(line) != nil {
                var items: [String] = []
                var j = i
                while j < lines.count, let t = numberedText(lines[j].trimmingCharacters(in: .whitespaces)) {
                    items.append(t)
                    j += 1
                }
                blocks.append(.numberedList(items))
                i = j
                continue
            }

            // Paragraph: consecutive plain lines until a blank line or a block marker starts.
            var para: [String] = []
            var j = i
            while j < lines.count {
                let t = lines[j].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || headingLevel(t) != nil || isBullet(t) || numberedText(t) != nil || isTableRow(t) {
                    break
                }
                para.append(lines[j])
                j += 1
            }
            blocks.append(.paragraph(para.joined(separator: "\n")))
            i = j
        }
        return blocks
    }

    private static func headingLevel(_ line: String) -> (level: Int, text: String)? {
        var count = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#" { count += 1; idx = line.index(after: idx) }
        guard count > 0, count <= 6, idx < line.endIndex, line[idx] == " " else { return nil }
        let text = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (min(count, 3), text)   // visually capped at H3 — cards are small, deeper nesting is noise
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ")
    }
    private static func bulletText(_ line: String) -> String { String(line.dropFirst(2)) }

    private static func numberedText(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex else { return nil }
        let prefix = line[line.startIndex..<dot]
        guard prefix.allSatisfy(\.isNumber) else { return nil }
        let after = line.index(after: dot)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return String(line[line.index(after: after)...])
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
    }
    private static func isSeparatorRow(_ line: String) -> Bool {
        let cells = splitRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { c in
            let s = c.trimmingCharacters(in: .whitespaces)
            return !s.isEmpty && s.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }
    private static func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: HTML / images

    /// Parses a Markdown `![alt](src)` or an HTML `<img …>` (the whole line) into an image.
    private static func imageFrom(_ line: String) -> (src: String, alt: String)? {
        // Markdown: ![alt](src)
        if line.hasPrefix("!["), let close = line.firstIndex(of: "]"),
           let open = line[close...].firstIndex(of: "("), line.hasSuffix(")") {
            let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close])
            let src = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
            return src.isEmpty ? nil : (src, alt)
        }
        // HTML: <img ... src="..." ... alt="...">
        let lower = line.lowercased()
        guard lower.hasPrefix("<img"), let src = htmlAttribute("src", in: line) else { return nil }
        return (src, htmlAttribute("alt", in: line) ?? "")
    }

    /// Extracts an HTML attribute value (double- or single-quoted).
    private static func htmlAttribute(_ name: String, in tag: String) -> String? {
        for quote in ["\"", "'"] {
            let needle = "\(name)=\(quote)"
            if let r = tag.range(of: needle, options: .caseInsensitive),
               let end = tag[r.upperBound...].range(of: quote) {
                return String(tag[r.upperBound..<end.lowerBound])
            }
        }
        return nil
    }

    /// If the line is an opening `<div align="…">`, returns its alignment (nil otherwise).
    private static func divAlignOpen(_ line: String) -> MDAlign? {
        guard line.lowercased().hasPrefix("<div"), line.hasSuffix(">"),
              let align = htmlAttribute("align", in: line) else { return nil }
        return MDAlign(html: align)
    }

    /// True for a line that is purely a structural HTML tag or comment (no content we render).
    private static func isStructuralHTMLLine(_ line: String) -> Bool {
        if line.hasPrefix("<!--") { return true }
        guard line.hasPrefix("<"), line.hasSuffix(">") else { return false }
        // A single tag: the only '>' is the last character (so it's one tag, not prose with markup).
        guard line.firstIndex(of: ">") == line.index(before: line.endIndex) else {
            // A matched wrapper like "<b>text</b>" alone on a line — strip only if it's a known tag pair.
            return false
        }
        let structural = ["div", "/div", "p", "/p", "br", "hr", "span", "/span", "center", "/center",
                          "picture", "/picture", "source", "table", "/table", "tr", "/tr", "td", "/td",
                          "th", "/th", "thead", "/thead", "tbody", "/tbody", "a", "/a"]
        let inner = line.dropFirst().dropLast().lowercased()   // e.g. `div align="center"` or `/div`
        let tagName = inner.prefix { $0 != " " }
        return structural.contains(String(tagName))
    }

    /// Removes inline HTML tags from text (keeps the inner text), so `<b>x</b>` renders as `x`. Only
    /// strips real tags (`<` immediately followed by a letter or `/`), leaving `a < b` comparisons alone.
    static func stripInlineHTML(_ text: String) -> String {
        guard text.contains("<") else { return text }
        guard let re = try? NSRegularExpression(pattern: "</?[a-zA-Z][^>]*>") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}

/// Renders parsed blocks with the app's flat visual language: no ASCII table borders, thin dividers,
/// a semibold header row. Sits inside whatever scroll/height container the caller provides.
struct MarkdownView: View {
    let blocks: [MDBlock]
    /// Base folder for resolving RELATIVE image paths (e.g. a note's own folder). Remote http(s)
    /// images load regardless; local relative ones need this. nil → relative images are skipped.
    var baseURL: URL? = nil
    /// Horizontal alignment for this group (set by an enclosing `<div align>`); defaults to leading.
    var align: MDAlign = .leading

    var body: some View {
        VStack(alignment: align.hStack, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: align.frame)
        .multilineTextAlignment(align == .center ? .center : (align == .trailing ? .trailing : .leading))
    }

    @ViewBuilder private func render(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let t):
            inline(t).font(headingFont(level)).fontWeight(.semibold)
        case .paragraph(let t):
            inline(t).font(.callout).lineSpacing(3)
        case .image(let src, let alt):
            MarkdownImage(src: src, alt: alt, baseURL: baseURL)
        case .aligned(let align, let inner):
            // A concrete MarkdownView (not a recursive call to `render`, which would make the opaque
            // return type reference itself) renders the wrapped blocks with the alignment applied.
            MarkdownView(blocks: inner, baseURL: baseURL, align: align)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Color.secondary).frame(width: 3.5, height: 3.5)
                            .padding(.top, 7).padding(.leading, 2)
                        inline(item).font(.callout).lineSpacing(3)
                    }
                }
            }
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        inline(item).font(.callout).lineSpacing(3)
                    }
                }
            }
        case .table(let headers, let rows):
            MarkdownTable(headers: headers, rows: rows)
        case .code(let s):
            Text(s).font(.system(.caption, design: .monospaced)).foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)   // don't wrap — keep the alignment
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center) // centre the block (ASCII diagrams)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3
        case 2: return .headline
        default: return .callout.weight(.semibold)
        }
    }

    private func inline(_ raw: String) -> Text {
        let s = MarkdownParser.stripInlineHTML(raw)   // drop any leftover inline tags (<b>, <a>, …)
        if let attr = try? AttributedString(markdown: s,
                                             options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }
}

/// A rendered image from Markdown/HTML: remote (http/https, cached to disk for offline use), or a
/// local file relative to the note's folder. Falls back to a subtle alt-text placeholder.
private struct MarkdownImage: View {
    let src: String
    let alt: String
    let baseURL: URL?

    var body: some View {
        if let url = URL(string: src), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            CachedRemoteImage(url: url, alt: alt)
        } else if let base = baseURL, let image = nidusLoadImage(at: base.appendingPathComponent(src)) {
            image.resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 340)
        } else {
            ImagePlaceholder(alt: alt)
        }
    }
}

private struct ImagePlaceholder: View {
    let alt: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo").foregroundStyle(.tertiary)
            Text(alt.isEmpty ? "Image" : alt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

/// A remote image that's cached to disk on first fetch, so it renders instantly and works offline
/// afterwards (never re-downloaded once cached).
private struct CachedRemoteImage: View {
    let url: URL
    let alt: String
    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFit().frame(maxWidth: .infinity).frame(maxHeight: 340)
            } else if failed {
                ImagePlaceholder(alt: alt)
            } else {
                ProgressView().frame(maxWidth: .infinity).frame(height: 60)
                    .task { await load() }
            }
        }
    }

    private func load() async {
        let cached = RemoteImageCache.fileURL(for: url)
        if !FileManager.default.fileExists(atPath: cached.path) {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                await MainActor.run { failed = true }; return
            }
            try? data.write(to: cached)
        }
        if let img = nidusLoadImage(at: cached) { await MainActor.run { image = img } }
        else { await MainActor.run { failed = true } }
    }
}

/// On-disk cache for remote images referenced in notes (in Caches/, keyed by a hash of the URL).
enum RemoteImageCache {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NidusRemoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return dir.appendingPathComponent("\(name).\(ext)")
    }
}

/// A clean table: a header rule and a faint divider between rows so columns line up and read clearly.
private struct MarkdownTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 9) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                    cell(h).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            GridRow { Divider().opacity(0.5).gridCellColumns(max(headers.count, 1)) }
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, c in
                        cell(c).font(.callout)
                    }
                }
                if idx < rows.count - 1 {
                    GridRow { Divider().opacity(0.14).gridCellColumns(max(headers.count, 1)) }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func cell(_ s: String) -> Text {
        if let attr = try? AttributedString(markdown: s,
                                             options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }
}
