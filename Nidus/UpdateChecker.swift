//
//  UpdateChecker.swift
//  Nidus
//
//  Tells you when a newer Nidus has been released. It does NOT update anything: Nidus is distributed
//  as a plain .app you moved to /Applications yourself, and an app that silently rewrites its own
//  binary is exactly the kind of thing this project doesn't do. So it checks, says so once, and links
//  you to the release page — you decide.
//
//  It is the only network request Nidus makes on its own behalf. It sends nothing: an unauthenticated
//  GET to a public GitHub endpoint, no identifier, no vault data, no analytics. Turn it off in the
//  Greeting Panel and it never fires again.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class UpdateChecker {
    /// The newest release, set ONLY when it's actually newer than what's running. Nil means "nothing to
    /// say" — an up-to-date app should be silent, not reassuring.
    private(set) var available: Update?

    struct Update: Equatable {
        let version: String
        let url: URL
    }

    private let enabledKey = "nidus.updates.check"
    private let lastCheckKey = "nidus.updates.lastCheck"
    private let skippedKey = "nidus.updates.skipped"
    private let defaults = UserDefaults.standard
    private let endpoint = URL(string: "https://api.github.com/repos/ParamoStudio/Nidus/releases/latest")!

    /// Opt-out, defaulting to on. `object(forKey:)` rather than `bool(forKey:)` — the latter reads a
    /// missing key as `false`, which would silently disable the check for everyone who never touched it.
    var enabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: enabledKey)
            if !newValue { available = nil }
        }
    }

    /// What's running, from the bundle — never hardcoded, so a release can't ship claiming to be old.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Once a day at most. Opening Nidus twenty times in a morning is normal; twenty requests aren't
    /// (GitHub rate-limits unauthenticated callers by IP, and the answer can't change that fast).
    func checkIfDue() async {
        guard enabled else { return }
        let last = defaults.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 60 * 60 * 24 else { return }
        await check()
    }

    func check() async {
        guard enabled else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String,
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true
        else { return }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.isNewer(version, than: currentVersion),
              defaults.string(forKey: skippedKey) != version
        else { return }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/ParamoStudio/Nidus/releases/latest")!
        available = Update(version: version, url: page)
    }

    /// Stop mentioning THIS version. A newer one will still speak up.
    func skip() {
        if let version = available?.version { defaults.set(version, forKey: skippedKey) }
        available = nil
    }

    /// Numeric, component-wise: "1.10" is newer than "1.9", which a string compare gets backwards.
    /// Missing components count as zero, so "1.1" and "1.1.0" are the same version.
    /// `nonisolated`: pure arithmetic on two strings, with no reason to need the main actor.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
