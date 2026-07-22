//
//  Card.swift
//  Nidus
//
//  The universal card — the unit of content every tool shares (NIDUS-tools-guideline §2). A card is
//  a Markdown block: a `## title`, a hidden `<!-- nidus:{…} -->` metadata comment, and a Markdown
//  body. Tools read the canonical fields they care about and PRESERVE the rest, so a card moves
//  between tools losslessly. `CardStore` parses/serialises a tool's `.md` as a list of cards while
//  keeping the file's self-describing tool header intact.
//

import Foundation

/// A link attached to a card: a friendly `title` + the raw `url` the user pasted.
struct CardLink: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var title: String
    var url: String

    enum CodingKeys: String, CodingKey { case title, url }
}

extension String {
    /// Adds `https://` when there's no scheme, so a pasted "www.google.com" actually opens.
    var asOpenableURL: URL? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }
}

/// A short display title derived from a URL's host (e.g. "www.google.com" → "google.com").
func linkDisplayTitle(for urlString: String) -> String {
    if let host = urlString.asOpenableURL?.host {
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    return urlString.trimmingCharacters(in: .whitespaces)
}

struct Card: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var body: String            // markdown notes/text
    var images: [String]        // relative paths, e.g. "_assets/<id>.png"; images[0] is the cover
    var links: [CardLink]       // interesting URLs (with a friendly title) attached to the card
    var created: Date
    var modified: Date
    var origin: String?         // last tool id it came from (minimal traceability)
    var extra: [String: String] // tool-specific fields (due, class, dateScope…), preserved verbatim

    /// A fresh card with a stable id and now() timestamps.
    static func make(title: String, body: String = "", origin: String? = nil) -> Card {
        let now = Date()
        return Card(id: UUID().uuidString, title: title, body: body, images: [], links: [],
                    created: now, modified: now, origin: origin, extra: [:])
    }
}

/// Reads/writes a tool's `.md` as an ordered list of cards, preserving the tool's header.
enum CardStore {

    // MARK: - Read

    static func read(from url: URL) -> [Card] {
        parse((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    // MARK: - Mutations (read → change → write back, keeping order + header)

    static func append(_ card: Card, to url: URL) {
        var cards = read(from: url)
        cards.append(card)
        write(cards, to: url)
    }

    static func update(_ card: Card, in url: URL) {
        var cards = read(from: url)
        guard let i = cards.firstIndex(where: { $0.id == card.id }) else { return }
        var c = card
        c.modified = Date()
        cards[i] = c
        write(cards, to: url)
    }

    static func remove(id: String, from url: URL) {
        var cards = read(from: url)
        cards.removeAll { $0.id == id }
        write(cards, to: url)
    }

    /// Persists the list, keeping whatever self-describing header (`# name`, `Tool:`…) the file had.
    static func write(_ cards: [Card], to url: URL) {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var out = header(of: existing)
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        for card in cards {
            out += "\n## \(card.title)\n"
            if let json = encodeMeta(card) { out += "<!-- nidus:\(json) -->\n" }
            let body = card.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { out += "\n\(body)\n" }
        }
        try? Data(out.utf8).write(to: url, options: .atomic)
    }

    // MARK: - Parsing

    /// Whether line `i` opens a new card. A card heading is `## title`; but note bodies can now
    /// contain their OWN Markdown `##`/`###` headings, so a heading is only a CARD boundary when it's
    /// immediately followed by the card's `<!-- nidus:… -->` metadata comment (which the app always
    /// writes). Legacy/hand-authored files with no metadata at all fall back to "every `## ` is a
    /// card". This is what stops a heading typed inside a note from splitting the card in two.
    private static func isCardHeading(_ lines: [String], _ i: Int, hasMeta: Bool) -> Bool {
        guard lines[i].hasPrefix("## ") else { return false }
        if !hasMeta { return true }
        let next = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : ""
        return next.hasPrefix("<!-- nidus:")
    }

    private static func fileHasMeta(_ lines: [String]) -> Bool {
        lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("<!-- nidus:") }
    }

    /// Everything before the first card heading is the tool's header (kept verbatim on write).
    private static func header(of text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let hasMeta = fileHasMeta(lines)
        var head: [String] = []
        var i = 0
        while i < lines.count, !isCardHeading(lines, i, hasMeta: hasMeta) {
            head.append(lines[i]); i += 1
        }
        return head.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    private static func parse(_ text: String) -> [Card] {
        let lines = text.components(separatedBy: "\n")
        let hasMeta = fileHasMeta(lines)
        var cards: [Card] = []
        var i = 0
        while i < lines.count && !isCardHeading(lines, i, hasMeta: hasMeta) { i += 1 }
        while i < lines.count {
            let title = String(lines[i].dropFirst(3)).trimmingCharacters(in: .whitespaces)
            i += 1
            var meta = CardMeta.fresh()
            if i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("<!-- nidus:"), l.hasSuffix("-->") {
                    let json = String(l.dropFirst("<!-- nidus:".count).dropLast("-->".count))
                        .trimmingCharacters(in: .whitespaces)
                    if let decoded = decodeMeta(json) { meta = decoded }
                    i += 1
                }
            }
            var bodyLines: [String] = []
            while i < lines.count && !isCardHeading(lines, i, hasMeta: hasMeta) {
                bodyLines.append(lines[i]); i += 1
            }
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            cards.append(Card(id: meta.id, title: title, body: body, images: meta.images,
                              links: meta.links ?? [], created: meta.created, modified: meta.modified,
                              origin: meta.origin, extra: meta.extra))
        }
        return cards
    }

    // MARK: - Metadata (the hidden comment)

    private struct CardMeta: Codable {
        var id: String
        var created: Date
        var modified: Date
        var origin: String?
        var images: [String]
        var links: [CardLink]?
        var extra: [String: String]

        init(id: String, created: Date, modified: Date, origin: String?,
             images: [String], links: [CardLink]?, extra: [String: String]) {
            self.id = id; self.created = created; self.modified = modified; self.origin = origin
            self.images = images; self.links = links; self.extra = extra
        }

        /// Defaults for a card whose comment is missing/corrupt (still usable, never crashes).
        static func fresh() -> CardMeta {
            let now = Date()
            return CardMeta(id: UUID().uuidString, created: now, modified: now,
                            origin: nil, images: [], links: nil, extra: [:])
        }

        enum CodingKeys: String, CodingKey { case id, created, modified, origin, images, links, extra }

        // Tolerant decode: missing/newer fields don't break older cards, and `links` reads either the
        // new [CardLink] format or the older [String] (URLs) — so nothing loses its id/origin.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let now = Date()
            id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
            created = (try? c.decode(Date.self, forKey: .created)) ?? now
            modified = (try? c.decode(Date.self, forKey: .modified)) ?? now
            origin = try? c.decode(String.self, forKey: .origin)
            images = (try? c.decode([String].self, forKey: .images)) ?? []
            extra = (try? c.decode([String: String].self, forKey: .extra)) ?? [:]
            if let typed = try? c.decode([CardLink].self, forKey: .links) {
                links = typed
            } else if let urls = try? c.decode([String].self, forKey: .links) {
                links = urls.map { CardLink(title: linkDisplayTitle(for: $0), url: $0) }
            } else {
                links = nil
            }
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func encodeMeta(_ card: Card) -> String? {
        let meta = CardMeta(id: card.id, created: card.created, modified: card.modified,
                            origin: card.origin, images: card.images, links: card.links, extra: card.extra)
        guard let data = try? encoder.encode(meta) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeMeta(_ json: String) -> CardMeta? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(CardMeta.self, from: data)
    }
}
