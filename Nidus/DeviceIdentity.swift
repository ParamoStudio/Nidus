//
//  DeviceIdentity.swift
//  Nidus
//
//  Local device identity (Blueprint §2.3 / §9.7).
//  "Who am I" lives ONLY locally (UserDefaults), NEVER in the synced vault.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Stable identity of this Nidus installation.
/// `id` is an immutable UUID; `name` is human-readable and user-editable.
struct DeviceIdentity: Codable, Equatable, Sendable {
    let id: String
    var name: String
}

/// Persists the device identity in `UserDefaults`.
/// Doctrine: this is the only genuinely local, per-machine state. Never written to the vault.
enum DeviceIdentityStore {
    private static let idKey = "nidus.device.id"
    private static let nameKey = "nidus.device.name"

    /// Returns the existing identity or creates it on first launch.
    static func loadOrCreate() -> DeviceIdentity {
        let defaults = UserDefaults.standard

        let id: String
        if let existing = defaults.string(forKey: idKey) {
            id = existing
        } else {
            id = UUID().uuidString
            defaults.set(id, forKey: idKey)
        }

        let name: String
        if let existing = defaults.string(forKey: nameKey) {
            name = existing
        } else {
            name = defaultDeviceName()
            defaults.set(name, forKey: nameKey)
        }

        return DeviceIdentity(id: id, name: name)
    }

    /// Renames the device (user-editable name).
    static func updateName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: nameKey)
    }

    /// Default name = the machine's name, per platform.
    private static func defaultDeviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }
}
