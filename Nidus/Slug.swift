//
//  Slug.swift
//  Nidus
//
//  Derives folder names and readable ids from the display name.
//  "Cerámica" → "ceramica"; "Óculo" → "oculo". No accents, lowercase, hyphens.
//

import Foundation

enum Slug {
    /// Converts a display name into a folder/id-safe slug.
    static func make(_ input: String) -> String {
        let folded = input.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
        var result = ""
        var lastWasHyphen = false
        for scalar in folded.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                result.append("-")
                lastWasHyphen = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "item" : trimmed
    }

    /// Ensures uniqueness against an existing set: `base`, `base-2`, `base-3`…
    static func unique(_ base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}
