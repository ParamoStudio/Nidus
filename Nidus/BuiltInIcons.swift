//
//  BuiltInIcons.swift
//  Nidus
//
//  Hardcoded icon set bundled with the app (asset catalog, template-rendered so they adopt the
//  dark/light tint like everything else). Shown first in the icon picker. Stored as "builtin:<name>".
//

import Foundation

enum BuiltInIcons {
    /// Asset names, in display order.
    static let names = [
        "icono1", "icono2", "icono3", "icono4", "icono5",
        "icono6", "icono7", "icono8", "icono9", "icono10"
    ]

    /// The asset name if `icon` is "builtin:<name>".
    static func name(_ icon: String?) -> String? {
        guard let icon, icon.hasPrefix("builtin:") else { return nil }
        return String(icon.dropFirst("builtin:".count))
    }
}
