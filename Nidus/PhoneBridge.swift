//
//  PhoneBridge.swift
//  Nidus
//
//  Pairs a phone with this vault so you can capture into a project's Inbox or Tasks while away from the
//  computer. Nidus stays the source of truth: it pushes a small read-only reference payload DOWN (which
//  projects exist, which tags exist) and pulls captured records UP, filing each one into the real `.md`
//  and only THEN telling the relay to drop it (the confirmation round trip — nothing is deleted on the
//  strength of "we uploaded it").
//
//  The relay is a dumb mailbox (see relay/README.md). The pairing token IS the credential; it lives in
//  UserDefaults because a pairing belongs to this device, not to the vault (the vault syncs; the pairing
//  shouldn't). Because the desktop deletes what it consumes, two devices running Nidus never double-import:
//  whichever opens first takes the records and the other finds an empty box.
//

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit
import SwiftUI

enum BridgeConfig {
    /// Where the phone web app is served from. The QR points here with the pairing in the hash.
    static let phoneAppBase = "https://paramostudio.github.io/Nidus/"
    /// The relay Nidus ships with. Anyone can point at their own instead (panel → Advanced → verified with
    /// a write-then-read probe); see relay/README.md. Empty here would mean "no relay until you deploy one".
    static let defaultRelayBase = "https://nidus-inbox.paramoyermo.workers.dev"
}

@MainActor
@Observable
final class PhoneBridge {
    private let tokenKey = "nidus.bridge.token"
    private let relayKey = "nidus.bridge.relay"
    private let pushedHashKey = "nidus.bridge.pushedHash"
    private let defaults = UserDefaults.standard

    /// Set while a sync is in flight, so the UI can say "checking…".
    private(set) var busy = false
    /// A short, human sentence about the last sync ("2 new, 1 updated"). Surfaced in the panel — an
    /// import that happens silently reads as a glitch.
    private(set) var lastMessage: String?

    // MARK: Pairing state

    var token: String {
        if let t = defaults.string(forKey: tokenKey), !t.isEmpty { return t }
        let fresh = Self.makeToken()
        defaults.set(fresh, forKey: tokenKey)
        return fresh
    }

    /// The relay this vault pairs through. Empty means "not set up yet".
    var relayBase: String {
        get {
            let stored = defaults.string(forKey: relayKey) ?? ""
            return stored.isEmpty ? BridgeConfig.defaultRelayBase : stored
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: relayKey)
            defaults.removeObject(forKey: pushedHashKey)   // a new relay is an empty mailbox
        }
    }

    var isConfigured: Bool { !relayBase.isEmpty }

    /// Scanning this pairs the phone AND tells it which relay to use — so switching relays just means
    /// re-scanning; nothing is ever typed on the phone.
    var pairingURL: String {
        let relay = relayBase.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return "\(BridgeConfig.phoneAppBase)#pair=\(token)~\(relay)"
    }

    /// The same pairing, carriable by hand. REQUIRED on iOS: a home-screen web app gets its own storage
    /// container, so a pairing made in Safari is invisible to the installed app.
    var pairingCode: String { "NI-" + Self.base64url(Data("\(token)~\(relayBase)".utf8)) }

    /// Forget this pairing and start a new one (every paired phone stops working).
    func regeneratePairing() {
        defaults.set(Self.makeToken(), forKey: tokenKey)
        defaults.removeObject(forKey: pushedHashKey)
        lastMessage = nil
    }

    // MARK: Push (reference payload → phone)

    /// Sends the project + tag list, but only when it actually changed (a cheap dirty flag that keeps the
    /// free-tier write budget for real traffic). Structure only — never card contents.
    @discardableResult
    func pushDown(_ model: NidusModel, force: Bool = false) async -> Bool {
        guard isConfigured else { return false }
        // Hash only the STABLE part: a `pushedAt` timestamp inside it would change every time and the
        // dirty flag would never fire. SHA256, not hashValue — Swift seeds Hasher per process, so
        // hashValue would differ on every launch and we'd re-push the same payload forever.
        let stable = referencePayload(model)
        guard let stableData = try? JSONSerialization.data(withJSONObject: stable, options: [.sortedKeys]) else { return false }
        let hash = SHA256.hash(data: stableData).map { String(format: "%02x", $0) }.joined()
        if !force, defaults.string(forKey: pushedHashKey) == hash { return true }   // unchanged

        var body = stable
        body["pushedAt"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        do {
            _ = try await send("PUT", "down", body: data)
            defaults.set(hash, forKey: pushedHashKey)
            return true
        } catch { return false }
    }

    private func referencePayload(_ model: NidusModel) -> [String: Any] {
        var projects: [[String: Any]] = []
        for hit in model.allProjects where ProjectStatus(hit.project.status) == .active {
            let grid = hit.project.layout?.grid ?? []
            projects.append([
                "id": hit.project.id,
                "name": hit.project.name,
                "discipline": hit.discipline.name,
                "inbox": grid.contains { $0.tool == "inbox" },
                "tasks": grid.contains { $0.tool == "task-manager" },
            ])
        }
        let tags = (model.config?.tags ?? []).map { ["id": $0.id, "name": $0.name] }
        return ["v": 1, "projects": projects, "tags": tags]   // `pushedAt` is added at send time
    }

    // MARK: Pull (captures → the real `.md` files)

    /// Files everything waiting, then confirms each one so the phone can drop its copy. Non-blocking:
    /// call it on app open and from the panel.
    @discardableResult
    func pullUp(_ model: NidusModel) async -> Int {
        guard isConfigured, !busy else { return 0 }
        busy = true
        defer { busy = false }
        do {
            let data = try await send("GET", "up", body: nil)
            let records = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            var filed = 0
            for record in records {
                guard let id = record["id"] as? String else { continue }
                if importRecord(record, model) {
                    // Only now is it safe to let the relay forget it.
                    _ = try? await send("DELETE", "up?id=\(id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id)", body: nil)
                    filed += 1
                }
            }
            if filed > 0 { model.notifyFileChange() }
            lastMessage = filed == 0 ? "Nothing waiting." : "Filed \(filed) capture\(filed == 1 ? "" : "s") from your phone."
            return filed
        } catch {
            lastMessage = "Couldn't reach the relay."
            return 0
        }
    }

    /// Turns one phone record into a real card in the project's Inbox or Task Manager.
    private func importRecord(_ record: [String: Any], _ model: NidusModel) -> Bool {
        guard let projectID = record["projectID"] as? String,
              let kind = record["kind"] as? String,
              let rawTitle = record["title"] as? String else { return false }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let hit = model.allProjects.first(where: { $0.project.id == projectID }),
              let file = targetFile(for: hit, kind: kind, model: model) else { return false }

        let body = (record["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var card = Card.make(title: title, body: body, origin: kind == "task" ? "task-manager" : "inbox")
        if kind == "task" {
            if let tags = record["tags"] as? [String], !tags.isEmpty { card.tagIDs = tags }
            if let ds = record["dueDate"] as? String, let date = ISO8601DateFormatter().date(from: ds),
               let scopeRaw = record["dueScope"] as? String, let scope = DeadlineScope(rawValue: scopeRaw) {
                card.deadline = TaskDeadline(date: date, scope: scope)
            }
            if let note = record["dueNote"] as? String, !note.isEmpty { card.deadlineNote = note }
        }
        CardStore.append(card, to: file)
        return true
    }

    /// The `.md` a capture lands in: the project's Inbox, or its FIRST Task Manager's todo file.
    private func targetFile(for hit: ProjectHit, kind: String, model: NidusModel) -> URL? {
        let toolID = kind == "task" ? "task-manager" : "inbox"
        guard let folder = model.projectFolderURL(hit.ref),
              let slot = (hit.project.layout?.grid ?? []).first(where: { $0.tool == toolID }) else { return nil }
        let declared = ToolRegistry.descriptor(for: toolID).files.first ?? "inbox.md"
        return folder.appendingPathComponent(slot.files?.first ?? declared)
    }

    // MARK: Relay plumbing

    /// A URL that merely returns 200 (a parked domain, a proxy, a generic KV worker) is NOT a relay —
    /// only a write-then-read probe proves it. Used by the Advanced section before accepting a URL.
    func verifyRelay(_ base: String) async -> Bool {
        let trimmed = base.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let root = URL(string: trimmed) else { return false }
        let probeToken = "probe" + Self.makeToken().prefix(16)
        let stamp = UUID().uuidString
        let url = root.appendingPathComponent("channel/\(probeToken)/down")
        do {
            var put = URLRequest(url: url); put.httpMethod = "PUT"
            put.httpBody = try JSONSerialization.data(withJSONObject: ["probe": stamp])
            put.setValue("application/json", forHTTPHeaderField: "Content-Type")
            _ = try await URLSession.shared.data(for: put)
            let (data, _) = try await URLSession.shared.data(from: url)
            let got = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return got?["probe"] as? String == stamp
        } catch { return false }
    }

    @discardableResult
    private func send(_ method: String, _ suffix: String, body: Data?) async throws -> Data {
        let base = relayBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/channel/\(token)/\(suffix)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: Helpers

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 18)   // 18 bytes → 24 base64url chars, matches TOKEN_RE
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - QR (CoreImage — no dependency)

func nidusQRImage(_ string: String, scale: CGFloat = 8) -> Image? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
          let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
    return Image(decorative: cg, scale: 1)
}
