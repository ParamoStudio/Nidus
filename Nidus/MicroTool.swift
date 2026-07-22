//
//  MicroTool.swift
//  Nidus
//
//  Micro-tools: tiny, modular, additive "Markdown templates + a small logic aid" that live INSIDE a
//  card's edit mode. A user can write one and import it; the app ships with the Glaze Normalizer as
//  the first example. Each micro-tool is a single self-contained `.js` file — chosen over an
//  executable format (.py etc.) because a bare JavaScriptCore context has NO filesystem/network/
//  system access, so running a community tool is safe, and it needs no bundled runtime or process.
//
//  The `.js` declares a global `tool` object with metadata + an input SCHEMA (so the app renders the
//  form generically, no per-tool Swift) + a pure `render(data)` returning a Markdown string. The
//  result is copied to the clipboard; the user pastes it (⌘V) into the note. Micro-tools are stored
//  vault-wide in `_microtools/`, so installing one makes it available in every project.
//

import Foundation
import JavaScriptCore

// MARK: - Model (parsed from a tool's `.js` schema)

struct MicroTool: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String            // SF Symbol
    let summary: String
    let inputs: [MicroInput]
    let sourceURL: URL
    var isBuiltIn = false        // shipped with Nidus → protected (can't be uninstalled, re-seeds)

    static func == (a: MicroTool, b: MicroTool) -> Bool {
        a.sourceURL == b.sourceURL && a.id == b.id && a.isBuiltIn == b.isBuiltIn
    }
}

struct MicroInput: Identifiable, Equatable {
    enum Kind: String { case text, textarea, number, table, grid, row, batch, picker }
    let id = UUID()
    let key: String
    let kind: Kind
    let label: String
    let placeholder: String
    let addLabel: String        // for tables: the "add row" button label
    let columns: [MicroColumn]  // for tables only
    let gridRows: Int           // for `grid`: initial row count (grows via + Row)
    let gridCols: Int           // for `grid`: initial column count (grows via + Column)
    var fields: [MicroInput] = []      // for `row`: scalar inputs rendered side by side on one line
    var maxLength: Int = 0             // for text: cap the length (0 = no cap)
    var options: [MicroOption] = []    // for `picker`: the choices
    var showWhen: MicroCondition? = nil // show this input only when another field equals a value
    var pickerStyle: String = ""       // for `picker`: "list" (default) | "chips" | "menu"
}

/// One choice in a `picker`. `value` is what `render` receives; `label` is what the user sees.
struct MicroOption: Identifiable, Equatable {
    let value: String
    let label: String
    var description: String = ""   // optional one-line use-case blurb, shown in the `list` style
    var id: String { value }
}

/// Conditional visibility: show the owning input only when `key`'s current value is one of `values`.
struct MicroCondition: Equatable {
    let key: String
    let values: [String]
}

struct MicroColumn: Identifiable, Equatable {
    let id = UUID()
    let key: String
    let label: String
    let numeric: Bool
}

// MARK: - Engine (JavaScriptCore — pure, sandboxed by construction)

enum MicroToolEngine {
    /// Parses a `.js` file into a `MicroTool` (metadata + schema). nil if it isn't a valid tool.
    static func load(_ url: URL) -> MicroTool? {
        guard let source = try? String(contentsOf: url, encoding: .utf8),
              let ctx = JSContext() else { return nil }
        ctx.evaluateScript(source)
        guard let tool = ctx.objectForKeyedSubscript("tool"), !tool.isUndefined,
              let dict = tool.toDictionary() else { return nil }
        guard let id = dict["id"] as? String, let name = dict["name"] as? String else { return nil }
        let inputs = (dict["inputs"] as? [[String: Any]] ?? []).compactMap(parseInput)
        return MicroTool(
            id: id, name: name,
            icon: (dict["icon"] as? String) ?? "wand.and.stars",
            summary: (dict["summary"] as? String) ?? "",
            inputs: inputs, sourceURL: url)
    }

    private static func parseInput(_ d: [String: Any]) -> MicroInput? {
        guard let kind = MicroInput.Kind(rawValue: (d["type"] as? String) ?? "text") else { return nil }

        // A `row` groups scalar sub-fields side by side on one line (no key of its own).
        if kind == .row {
            let fields = (d["fields"] as? [[String: Any]] ?? []).compactMap(parseInput)
            return MicroInput(key: "", kind: .row, label: "", placeholder: "", addLabel: "",
                              columns: [], gridRows: 2, gridCols: 2, fields: fields)
        }

        guard let key = d["key"] as? String else { return nil }
        let columns = (d["columns"] as? [[String: Any]] ?? []).compactMap { c -> MicroColumn? in
            guard let ck = c["key"] as? String else { return nil }
            return MicroColumn(key: ck, label: (c["label"] as? String) ?? ck,
                               numeric: (c["type"] as? String) == "number")
        }
        func intOf(_ keys: [String], _ fallback: Int) -> Int {
            for k in keys { if let n = d[k] as? Int { return max(1, n) }
                            if let n = d[k] as? Double { return max(1, Int(n)) } }
            return fallback
        }
        var maxLen = 0
        if let n = d["maxLength"] as? Int { maxLen = n }
        else if let n = d["maxLength"] as? Double { maxLen = Int(n) }
        let options = (d["options"] as? [[String: Any]] ?? []).compactMap { o -> MicroOption? in
            guard let v = o["value"] as? String else { return nil }
            return MicroOption(value: v, label: (o["label"] as? String) ?? v,
                                description: (o["description"] as? String) ?? "")
        }
        var showWhen: MicroCondition? = nil
        if let sw = d["showWhen"] as? [String: Any], let k = sw["key"] as? String {
            if let s = sw["equals"] as? String { showWhen = MicroCondition(key: k, values: [s]) }
            else if let arr = sw["equals"] as? [String] { showWhen = MicroCondition(key: k, values: arr) }
        }
        return MicroInput(
            key: key, kind: kind,
            label: (d["label"] as? String) ?? key,
            placeholder: (d["placeholder"] as? String) ?? "",
            addLabel: (d["addLabel"] as? String) ?? "Add row",
            columns: columns,
            gridRows: intOf(["rows", "minRows"], 2),
            gridCols: intOf(["cols", "columns", "minCols"], 2),
            maxLength: maxLen, options: options, showWhen: showWhen,
            pickerStyle: (d["style"] as? String)?.lowercased() ?? "")
    }

    /// Runs the tool's `render(data)` in a fresh context and returns the Markdown it produces.
    /// `data` values are strings (scalars) or arrays of `[column: string]` (tables) — the JS side
    /// does its own `parseFloat`, so we never have to bridge number types.
    static func render(_ tool: MicroTool, data: [String: Any]) -> String? {
        guard let source = try? String(contentsOf: tool.sourceURL, encoding: .utf8),
              let ctx = JSContext() else { return nil }
        var thrown: String?
        ctx.exceptionHandler = { _, exc in thrown = exc?.toString() }
        ctx.evaluateScript(source)
        guard let toolObj = ctx.objectForKeyedSubscript("tool"),
              let render = toolObj.objectForKeyedSubscript("render"),
              !render.isUndefined,
              let result = render.call(withArguments: [data]) else { return nil }
        if thrown != nil { return nil }
        return result.isString ? result.toString() : nil
    }
}

// MARK: - Store (vault-wide `_microtools/`, seeded with the built-in Glaze Normalizer)

enum MicroToolStore {
    static let folderName = "_microtools"
    /// Ids shipped with Nidus — protected from uninstall, and re-seeded if their file goes missing.
    static let builtInIDs: Set<String> = ["recipe-normalizer", "table-builder", "triaxial-calculator",
                                           "batch-renamer", "template-library"]

    static func folderURL(vaultURL: URL?) -> URL? {
        vaultURL?.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Ensures the folder exists, seeds the built-in tool(s) once, and returns every installed tool
    /// (built-ins first, then the rest alphabetically).
    static func installed(vaultURL: URL?) -> [MicroTool] {
        guard let folder = folderURL(vaultURL: vaultURL) else { return [] }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        seedDefaults(into: folder)
        guard let urls = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        let tools = urls
            .filter { $0.pathExtension.lowercased() == "js" }
            .compactMap { url -> MicroTool? in
                guard var t = MicroToolEngine.load(url) else { return nil }
                t.isBuiltIn = builtInIDs.contains(t.id)
                return t
            }
        return tools.sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn && !$1.isBuiltIn }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Removes a user-installed micro-tool's `.js`. Built-ins are protected (no-op).
    static func uninstall(_ tool: MicroTool) {
        guard !builtInIDs.contains(tool.id) else { return }
        try? FileManager.default.removeItem(at: tool.sourceURL)
    }

    /// Copies an imported `.js` into the store (unique name if it clashes). Returns the loaded tool.
    @discardableResult
    static func install(from src: URL, vaultURL: URL?) -> MicroTool? {
        guard src.pathExtension.lowercased() == "js",
              let folder = folderURL(vaultURL: vaultURL) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        var dest = folder.appendingPathComponent(src.lastPathComponent)
        var n = 1
        let stem = src.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(stem)-\(n).js"); n += 1
        }
        do { try FileManager.default.copyItem(at: src, to: dest) } catch { return nil }
        // Only keep it if it parses as a valid tool; otherwise remove the junk we just copied.
        guard let tool = MicroToolEngine.load(dest) else {
            try? FileManager.default.removeItem(at: dest); return nil
        }
        return tool
    }

    private static func seedDefaults(into folder: URL) {
        let fm = FileManager.default
        // Migrate the pre-release name if it's lying around from earlier testing.
        let legacy = folder.appendingPathComponent("glaze-normalizer.js")
        if fm.fileExists(atPath: legacy.path) { try? fm.removeItem(at: legacy) }

        seed("recipe-normalizer.js", recipeNormalizerJS, into: folder)
        seed("table-builder.js", tableBuilderJS, into: folder)
        seed("triaxial-calculator.js", triaxialCalculatorJS, into: folder)
        seed("batch-renamer.js", batchRenamerJS, into: folder)
        seed("template-library.js", templateLibraryJS, into: folder)
    }

    /// Built-ins are canonical: (re)write to the shipped version whenever it differs, so our updates
    /// propagate to existing vaults (they're protected from in-app edits anyway).
    private static func seed(_ name: String, _ js: String, into folder: URL) {
        let url = folder.appendingPathComponent(name)
        let current = try? String(contentsOf: url, encoding: .utf8)
        if current != js { try? Data(js.utf8).write(to: url, options: .atomic) }
    }
}
