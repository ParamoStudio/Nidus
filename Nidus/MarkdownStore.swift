//
//  MarkdownStore.swift
//  Nidus
//
//  Reads and writes the project's `.md` files (Blueprint §2.4, §2.8).
//  Standard Markdown only. Append/edit lines; never destroys user content. Completing a task
//  moves its line from tasks-todo.md to tasks-done.md (the one allowed line move).
//

import Foundation

/// A `## heading` and its lines, for display (inbox days, ideas blocks, archive days).
struct MarkdownSection: Identifiable {
    let id = UUID()
    let title: String
    var items: [String]
}

enum MarkdownStore {

    // MARK: - Read

    static func readString(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Lines that are part of the self-describing tool header, not content.
    private static func isMetadataLine(_ line: String) -> Bool {
        line.hasPrefix("# ") || line.hasPrefix("Tool:") || line.hasPrefix("Tool name:")
    }

    /// Parses `## heading` sections with their content lines (bullets stripped).
    static func readSections(from url: URL) -> [MarkdownSection] {
        var sections: [MarkdownSection] = []
        var current: MarkdownSection?
        for raw in readString(url).components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                if let c = current { sections.append(c) }
                current = MarkdownSection(title: String(line.dropFirst(3)), items: [])
            } else if line.isEmpty || isMetadataLine(line) {
                continue
            } else {
                let item = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
                current?.items.append(item)
            }
        }
        if let c = current { sections.append(c) }
        return sections
    }

    /// The self-describing header written at the top of every tool file (Tool type + name), so
    /// the file is legible without Nidus and an LLM can understand its context (user decision).
    static func toolFileHeader(toolID: String, name: String) -> String {
        "# \(name)\n\nTool: \(toolID)\nTool name: \(name)\n\n"
    }

    /// Creates a tool's `.md` with its self-describing header if it doesn't exist yet.
    static func ensureToolFile(at url: URL, toolID: String, name: String) throws {
        // Skip folder-token "files" (no extension) — a tool like Reference Board declares its storage
        // folder as an instance token so it can be duplicated, but manages that folder itself.
        guard !url.pathExtension.isEmpty else { return }
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try writeString(toolFileHeader(toolID: toolID, name: name), url)
    }

    /// Updates the `# <name>` title and `Tool name:` line in a tool file (on rename). Keeps the
    /// filename and `Tool:` type unchanged.
    static func renameHeader(at url: URL, to newName: String) throws {
        guard !url.pathExtension.isEmpty else { return }   // folder-token file (see ensureToolFile)
        var lines = readString(url).components(separatedBy: "\n")
        var renamedTitle = false
        for i in lines.indices {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if !renamedTitle, line.hasPrefix("# ") {
                lines[i] = "# \(newName)"
                renamedTitle = true
            } else if line.hasPrefix("Tool name:") {
                lines[i] = "Tool name: \(newName)"
            }
        }
        try writeString(lines.joined(separator: "\n"), url)
    }

    /// Marks a tool's `.md` as deprecated when its instance is abandoned: prefixes the `# <name>`
    /// title with `[deprecated]` and adds a `Deprecated: true` header line. The file is KEPT on disk
    /// (the notes are cheap to store and worth archiving); only the app's link to it is removed.
    /// Idempotent, and a no-op if the file doesn't exist (e.g. folder-based tools).
    static func markDeprecated(at url: URL) {
        guard !url.pathExtension.isEmpty else { return }   // folder-token file (see ensureToolFile)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var lines = readString(url).components(separatedBy: "\n")
        guard !lines.contains(where: { $0.hasPrefix("Deprecated:") }) else { return }   // already marked
        if let i = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            if !lines[i].contains("[deprecated]") { lines[i] = "# [deprecated] " + String(lines[i].dropFirst(2)) }
            let anchor = lines.firstIndex(where: { $0.hasPrefix("Tool name:") }) ?? i
            lines.insert("Deprecated: true", at: anchor + 1)
        } else {
            lines.insert("Deprecated: true", at: 0)
        }
        try? writeString(lines.joined(separator: "\n"), url)
    }

    /// Content lines (no headers/blank) that contain the query, for the command palette.
    static func searchLines(in url: URL, query: String) -> [String] {
        let needle = query.lowercased()
        return readString(url).components(separatedBy: "\n").compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            // Never surface hidden card metadata (`<!-- nidus:… -->`) or old header lines.
            if line.hasPrefix("<!--") || isMetadataLine(line) { return nil }
            // A card title (`## Foo`) IS searchable — by its text, not the raw heading. Other
            // headings (`# Tasks`, …) are skipped.
            if line.hasPrefix("## ") { line = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("#") { return nil }
            return line.lowercased().contains(needle) ? line : nil
        }
    }

    /// Active task texts parsed from `- [ ] …` lines.
    static func readTasks(from url: URL) -> [String] {
        readString(url).components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- [ ] ") else { return nil }
            return String(line.dropFirst(6))
        }
    }

    // MARK: - Write

    /// Inbox capture: appends `- text` under today's date heading.
    static func appendCapture(_ text: String, to url: URL) throws {
        try appendUnderTodayHeading("- \(text)", to: url, headingPrefix: "## ")
    }

    /// Ideas: appends a new dated block header (free markdown can be edited afterwards).
    static func appendIdea(_ title: String, to url: URL) throws {
        var content = readString(url)
        if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
        content += "\n## \(HumanDate.heading()) — \(title)\n"
        try writeString(content, url)
    }

    /// Ideas: appends a note line right under an existing idea's `## <date> — <title>` header.
    static func appendNote(_ note: String, underSectionTitled title: String, in url: URL) throws {
        var lines = readString(url).components(separatedBy: "\n")
        let header = "## \(title)"
        guard let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header })
        else { return }
        lines.insert("- \(note)", at: index + 1)
        try writeString(lines.joined(separator: "\n"), url)
    }

    /// Task Manager: appends an unchecked task.
    static func addTask(_ text: String, toTodo url: URL) throws {
        var content = readString(url)
        if content.isEmpty { content = "# Tasks\n" }
        if !content.hasSuffix("\n") { content += "\n" }
        content += "- [ ] \(text)\n"
        try writeString(content, url)
    }

    /// Completion: removes the task line from todo and appends it (checked) to done,
    /// under today's "## Completed: <date>" heading.
    static func completeTask(_ text: String, todoURL: URL, doneURL: URL) throws {
        var lines = readString(todoURL).components(separatedBy: "\n")
        if let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "- [ ] \(text)"
        }) {
            lines.remove(at: index)
            try writeString(lines.joined(separator: "\n"), todoURL)
        }
        try appendUnderTodayHeading("- [x] \(text)", to: doneURL, headingPrefix: "## Completed: ")
    }

    // MARK: - Helpers

    /// Ensures today's heading exists (creating it at the end if missing) and appends `line`.
    private static func appendUnderTodayHeading(_ line: String, to url: URL, headingPrefix: String) throws {
        var content = readString(url)
        let heading = headingPrefix + HumanDate.heading()
        if !content.contains(heading) {
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += "\n\(heading)\n"
        }
        if !content.hasSuffix("\n") { content += "\n" }
        content += "\(line)\n"
        try writeString(content, url)
    }

    private static func writeString(_ string: String, _ url: URL) throws {
        try Data(string.utf8).write(to: url, options: .atomic)
    }
}
