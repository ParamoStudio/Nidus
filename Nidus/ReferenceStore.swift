//
//  ReferenceStore.swift
//  Nidus
//
//  The Reference Board's single source of truth is a real folder — `Nidus References` — created
//  inside the PROJECT's own vault folder (next to the Notebook and `_assets/`), so it works for every
//  project and syncs. Whatever image files live there is
//  what the board shows. A hidden JSON marker (`.nidus-references`) stamps the folder's identity and
//  records each image's arrival time + the manual order. This helper does the filesystem side:
//  ensure the folder, list images (cheap size via ImageIO), reconcile the manifest, sort, add files,
//  and load cached, downsampled thumbnails (so re-layouts don't reload → no flicker).
//

import SwiftUI
import ImageIO
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// How the board orders images.
enum RefSort: String, CaseIterable, Identifiable {
    case arrival, created, manual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .arrival: return "Added"
        case .created: return "Created"
        case .manual: return "Manual"
        }
    }
}

enum ReferenceStore {
    static let folderName = "Nidus References"
    static let markerName = ".nidus-references"   // hidden identity + manifest
    static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp"]


    /// Ensures the folder + hidden manifest exist. Returns the folder, or nil if it couldn't be made.
    @discardableResult
    static func ensure(_ folder: URL) -> URL? {
        let fm = FileManager.default
        do {
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: folder.path, isDirectory: &isDir) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            } else if !isDir.boolValue {
                return nil
            }
            if !fm.fileExists(atPath: folder.appendingPathComponent(markerName).path) {
                saveManifest(Manifest(id: UUID().uuidString, order: [], arrival: [:]), folder)
            }
            return folder
        } catch { return nil }
    }

    // MARK: - Items

    /// One image file: url + pixel size + creation date. Cheap (no full decode).
    struct Item: Identifiable, Equatable {
        let url: URL
        let size: CGSize
        let created: Date
        var id: String { url.path }
        var name: String { url.lastPathComponent }
        var aspectRatio: CGFloat { size.height > 0 ? size.width / size.height : 1 }
    }

    /// All images in the folder (unsorted-ish; caller sorts). Skips hidden files/marker.
    static func items(in folder: URL) -> [Item] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { return [] }
        return urls.compactMap { url in
            guard imageExtensions.contains(url.pathExtension.lowercased()),
                  let size = pixelSize(url) else { return nil }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return Item(url: url, size: size, created: created)
        }
    }

    static func pixelSize(_ url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    // MARK: - Manifest (identity + arrival + manual order)

    struct Manifest: Codable {
        var id: String
        var order: [String]            // manual order (filenames)
        var arrival: [String: Date]    // filename → first time Nidus saw it
        var notes: [String: String]    // filename → a short "why is it here?" note

        init(id: String, order: [String], arrival: [String: Date], notes: [String: String] = [:]) {
            self.id = id; self.order = order; self.arrival = arrival; self.notes = notes
        }
        enum CodingKeys: String, CodingKey { case id, order, arrival, notes }
        init(from d: Decoder) throws {   // tolerant: older manifests have no `notes`
            let c = try d.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            order = (try? c.decode([String].self, forKey: .order)) ?? []
            arrival = (try? c.decode([String: Date].self, forKey: .arrival)) ?? [:]
            notes = (try? c.decode([String: String].self, forKey: .notes)) ?? [:]
        }
    }

    static func loadManifest(_ folder: URL) -> Manifest {
        let url = folder.appendingPathComponent(markerName)
        if let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(Manifest.self, from: data) { return m }
        // Migrate an old plain-UUID marker, or start fresh.
        let raw = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Manifest(id: (raw?.isEmpty == false ? raw! : UUID().uuidString), order: [], arrival: [:])
    }

    static func saveManifest(_ m: Manifest, _ folder: URL) {
        if let data = try? JSONEncoder().encode(m) {
            try? data.write(to: folder.appendingPathComponent(markerName))
        }
    }

    /// Reads the folder + manifest and reconciles them: new files get an arrival stamp + a slot in
    /// the manual order; vanished files are pruned. Returns the items and the up-to-date manifest.
    static func reconcile(_ folder: URL) -> (items: [Item], manifest: Manifest) {
        var m = loadManifest(folder)
        let items = items(in: folder)
        let names = Set(items.map(\.name))
        var changed = false

        let prunedOrder = m.order.filter { names.contains($0) }
        if prunedOrder.count != m.order.count { m.order = prunedOrder; changed = true }
        let prunedArrival = m.arrival.filter { names.contains($0.key) }
        if prunedArrival.count != m.arrival.count { m.arrival = prunedArrival; changed = true }
        let prunedNotes = m.notes.filter { names.contains($0.key) }
        if prunedNotes.count != m.notes.count { m.notes = prunedNotes; changed = true }

        // Add newcomers oldest-first, so arrival/manual order reads chronologically.
        for it in items.sorted(by: { $0.created < $1.created }) {
            if m.arrival[it.name] == nil {
                m.arrival[it.name] = it.created == .distantPast ? Date() : it.created
                changed = true
            }
            if !m.order.contains(it.name) { m.order.append(it.name); changed = true }
        }
        if changed { saveManifest(m, folder) }
        return (items, m)
    }

    /// Items ordered by the chosen mode. Manual = as arranged; Added/Created = newest first.
    static func sorted(_ items: [Item], _ m: Manifest, mode: RefSort) -> [Item] {
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        switch mode {
        case .manual:
            var result = m.order.compactMap { byName[$0] }
            let inOrder = Set(m.order)
            result += items.filter { !inOrder.contains($0.name) }
            return result
        case .arrival:
            return items.sorted { (m.arrival[$0.name] ?? $0.created) > (m.arrival[$1.name] ?? $1.created) }
        case .created:
            return items.sorted { $0.created > $1.created }
        }
    }

    /// Persist a new manual order (list of filenames).
    static func saveOrder(_ order: [String], _ folder: URL) {
        var m = loadManifest(folder)
        m.order = order
        saveManifest(m, folder)
    }

    /// Set (or clear) an image's short note.
    static func setNote(_ note: String, for name: String, in folder: URL) {
        var m = loadManifest(folder)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { m.notes[name] = nil } else { m.notes[name] = trimmed }
        saveManifest(m, folder)
    }

    // MARK: - Adding images (import / drop / paste)

    @discardableResult
    static func importFile(_ src: URL, into folder: URL) -> URL? {
        guard imageExtensions.contains(src.pathExtension.lowercased()) else { return nil }
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let dest = uniqueURL(in: folder, ext: src.pathExtension.isEmpty ? "png" : src.pathExtension)
        do { try FileManager.default.copyItem(at: src, to: dest); return dest } catch { return nil }
    }

    @discardableResult
    static func saveData(_ data: Data, ext: String, into folder: URL) -> URL? {
        let dest = uniqueURL(in: folder, ext: ext.isEmpty ? "png" : ext)
        do { try data.write(to: dest); return dest } catch { return nil }
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func uniqueURL(in folder: URL, ext: String) -> URL {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        var url = folder.appendingPathComponent("ref-\(stamp).\(ext)")
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("ref-\(stamp)-\(n).\(ext)"); n += 1
        }
        return url
    }

    // MARK: - Clipboard

    static func clipboardImagePNG() -> Data? {
        #if canImport(AppKit)
        if let img = NSImage(pasteboard: NSPasteboard.general),
           let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
        #elseif canImport(UIKit)
        return UIPasteboard.general.image?.pngData()
        #endif
    }

    static func clipboardImageURLs() -> [URL] {
        #if canImport(AppKit)
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        return urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        #else
        return []
        #endif
    }

    // MARK: - Thumbnails (cached → re-layouts don't reload, no flicker)

    static func loadThumbnailCG(_ url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

/// Process-wide thumbnail cache so re-measuring/re-laying-out the collage never reloads an image.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, Box>()
    private final class Box { let cg: CGImage; init(_ c: CGImage) { cg = c } }

    func cached(_ url: URL) -> CGImage? { cache.object(forKey: url.path as NSString)?.cg }
    func store(_ cg: CGImage, _ url: URL) { cache.setObject(Box(cg), forKey: url.path as NSString) }
}

/// A CGImage that can cross a task boundary (CGImage is thread-safe to read).
struct SendableCGImage: @unchecked Sendable { let cg: CGImage }
