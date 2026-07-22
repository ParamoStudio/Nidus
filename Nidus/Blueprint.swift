//
//  Blueprint.swift
//  Nidus
//
//  The "Current Blueprint" — a pinned, per-project focal point: not a grid tool, a small anchor that
//  answers "given everything we know, what are we actually making?" (WorkspaceView pins its pill in
//  identityCard's top-right corner). Structured by a TEMPLATE (Ceramic Product, Software, Research,
//  Exhibition…) so the fields fit the discipline. Self-contained versioning: saving keeps exactly ONE
//  step back (`previous`) so a doubt is a tap away from reverting, and a lightweight, ever-growing
//  `activity` trail records every update — a log, without building a whole history browser.
//

import Foundation

/// One labelled field in a blueprint (order preserved — templates aren't dictionaries). `included`
/// lets you annul a field you don't personally care about for this project: it stays in the form
/// (nothing is lost) but is skipped in the read view, same as an empty one.
struct BlueprintField: Codable, Equatable, Identifiable {
    /// A field is meant to be a one-line mental anchor, not an essay — this keeps the overview scannable.
    static let maxLength = 140

    var label: String
    var value: String = ""
    var included: Bool = true
    var id: String { label }

    enum CodingKeys: String, CodingKey { case label, value, included }
    init(label: String, value: String = "", included: Bool = true) {
        self.label = label; self.value = value; self.included = included
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        value = (try? c.decode(String.self, forKey: .value)) ?? ""
        included = (try? c.decode(Bool.self, forKey: .included)) ?? true   // older files predate this flag
    }
}

/// A reusable field layout for a kind of project. Four ship built-in; anyone can also IMPORT one as a
/// plain `.md`: a top `# Template Name` line, then one `## Field Label` per line — see `parse(markdown:)`.
struct BlueprintTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let hint: String            // one line shown on the picker
    let fieldLabels: [String]
    var isCustom: Bool = false

    static let builtIns: [BlueprintTemplate] = [
        BlueprintTemplate(id: "ceramic", name: "Ceramic Product", icon: "flame", hint: "Form, clay, glaze, firing, packaging",
                          fieldLabels: ["Goal", "Product", "Clay", "Glaze", "Firing", "Packaging", "Current Unknowns", "Success Criteria"]),
        BlueprintTemplate(id: "software", name: "Software", icon: "chevron.left.forwardslash.chevron.right", hint: "Users, platform, architecture, risks",
                          fieldLabels: ["Goal", "Users", "Platform", "Core Features", "Current Architecture", "Known Risks", "Definition of Done"]),
        BlueprintTemplate(id: "research", name: "Research", icon: "flask", hint: "Question, hypothesis, method, findings",
                          fieldLabels: ["Question", "Hypothesis", "Method", "Variables", "Current Findings", "Next Experiment"]),
        BlueprintTemplate(id: "exhibition", name: "Exhibition", icon: "photo.artframe", hint: "Concept, pieces, materials, installation",
                          fieldLabels: ["Concept", "Narrative", "Pieces", "Materials", "Installation", "Lighting", "Open Questions"]),
    ]

    /// Parses a `# Name` + `## Field` per line `.md` into a template. `id` is derived from the name so
    /// re-importing the same file updates the same template rather than duplicating it. The file may
    /// optionally declare an SF Symbol icon with a `<!-- icon: flask -->` comment (any line) so its
    /// picker tile matches the built-ins' look; otherwise a neutral default is used.
    static func parse(markdown: String, fallbackName: String) -> BlueprintTemplate? {
        var name = fallbackName
        var labels: [String] = []
        var icon: String?
        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let m = line.range(of: "^<!--\\s*icon:\\s*", options: .regularExpression) {
                icon = line[m.upperBound...].replacingOccurrences(of: "-->", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("# ") {
                name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("## ") {
                let label = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !label.isEmpty { labels.append(label) }
            }
        }
        guard !labels.isEmpty else { return nil }
        let slug = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        let symbol = (icon?.isEmpty == false) ? icon! : "square.grid.2x2"
        return BlueprintTemplate(id: "custom-\(slug)", name: name, icon: symbol,
                                 hint: labels.prefix(4).joined(separator: ", "), fieldLabels: labels, isCustom: true)
    }
}

/// Vault-root folder of imported `.md` templates — reusable across every project (same idea as the
/// `_library/` cross-project bank installed tools can use).
enum BlueprintTemplateStore {
    private static func folder(vault: URL) -> URL { vault.appendingPathComponent("_templates/blueprint", isDirectory: true) }

    static func customTemplates(vault: URL) -> [BlueprintTemplate] {
        let dir = folder(vault: vault)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "md" }.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8))
                .flatMap { BlueprintTemplate.parse(markdown: $0, fallbackName: url.deletingPathExtension().lastPathComponent) }
        }.sorted { $0.name < $1.name }
    }

    /// Copies a picked `.md` into the vault's template folder and parses it. nil if it has no `## ` fields.
    @discardableResult
    static func importTemplate(from sourceURL: URL, vault: URL) -> BlueprintTemplate? {
        guard let text = try? String(contentsOf: sourceURL, encoding: .utf8),
              let template = BlueprintTemplate.parse(markdown: text, fallbackName: sourceURL.deletingPathExtension().lastPathComponent)
        else { return nil }
        let dir = folder(vault: vault)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(template.id).md")
        try? text.write(to: dest, atomically: true, encoding: .utf8)
        return template
    }
}

/// One line in the activity trail — just enough to show "it changed, and when" without a full diff.
struct BlueprintActivity: Codable, Equatable {
    var version: Int
    var date: Date
    var note: String
}

/// A snapshot of fields + version, kept as `previous` for one-step revert.
struct BlueprintSnapshot: Codable, Equatable {
    var version: Int
    var fields: [BlueprintField]
    var approvedAt: Date
}

struct Blueprint: Codable, Equatable {
    var templateID: String
    var templateName: String     // denormalized: survives a future template rename/removal
    var fields: [BlueprintField]
    var version: Int
    var approvedAt: Date
    var previous: BlueprintSnapshot?
    var activity: [BlueprintActivity]

    static func fresh(template: BlueprintTemplate) -> Blueprint {
        let now = Date()
        return Blueprint(templateID: template.id, templateName: template.name,
                         fields: template.fieldLabels.map { BlueprintField(label: $0) },
                         version: 1, approvedAt: now, previous: nil,
                         activity: [BlueprintActivity(version: 1, date: now, note: "Blueprint created")])
    }

    /// Bumps to a new version: the current state becomes `previous`, the new fields become current, and
    /// the activity trail gets one more line. This is the ONLY way version advances.
    mutating func logUpdate(fields newFields: [BlueprintField]) {
        let now = Date()
        previous = BlueprintSnapshot(version: version, fields: fields, approvedAt: approvedAt)
        version += 1
        self.fields = newFields
        approvedAt = now
        activity.append(BlueprintActivity(version: version, date: now, note: "Blueprint updated"))
    }

    /// True when `previous` outranks the active version — i.e. swapping would move you FORWARD (back to
    /// the version you reverted away from), not backward. Drives the read view's button label/confirm.
    var swapGoesForward: Bool { (previous?.version ?? 0) > version }

    /// Swaps the active fields with `previous`. Both snapshots keep their OWN fixed version number —
    /// nothing is renumbered — so this is purely "which one is active" and stays strictly reversible:
    /// swapping twice always returns you exactly where you started. The direction (backward to a lower
    /// number vs. forward to a higher one) is read from `swapGoesForward` BEFORE calling this.
    mutating func swapWithPrevious() {
        guard let prev = previous else { return }
        let now = Date()
        let goingForward = swapGoesForward
        let currentAsSnapshot = BlueprintSnapshot(version: version, fields: fields, approvedAt: approvedAt)
        version = prev.version
        fields = prev.fields
        approvedAt = prev.approvedAt
        previous = currentAsSnapshot
        activity.append(BlueprintActivity(version: version, date: now,
                                          note: goingForward ? "Returned to v\(version)" : "Reverted to v\(version)"))
    }
}

/// Reads/writes a project's `blueprint.json` (project-root file, sibling of the tool `.md`s — not a
/// grid tool, so it isn't part of ProjectLayout).
enum BlueprintStore {
    private static func fileURL(projectFolder: URL) -> URL {
        projectFolder.appendingPathComponent("blueprint.json")
    }

    static func load(projectFolder: URL) -> Blueprint? {
        let url = fileURL(projectFolder: projectFolder)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Blueprint.self, from: data)
    }

    static func save(_ blueprint: Blueprint, projectFolder: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(blueprint) else { return }
        try? data.write(to: fileURL(projectFolder: projectFolder), options: .atomic)
    }

    /// Erases the blueprint entirely — "start over" (destructive; the caller double-confirms first).
    static func delete(projectFolder: URL) {
        try? FileManager.default.removeItem(at: fileURL(projectFolder: projectFolder))
    }
}
