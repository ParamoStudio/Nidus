//
//  HumanDate.swift
//  Nidus
//
//  Human, locale-aware date headings for the content of the .md files.
//  In the app's current language: "Monday, 5 May 2026" / "Lunes, 5 de mayo de 2026".
//  Never ISO 8601 in content (Blueprint §10.8). Section headers stay fixed English; only the
//  dates follow the app language (per the user's decision).
//

import Foundation

enum HumanDate {
    /// e.g. "Monday, 5 May 2026" in the app's effective language, first letter capitalized.
    /// Uses the app's preferred localization (not the raw system locale), so dates match the
    /// language the UI is actually showing.
    static func heading(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        let raw = formatter.string(from: date)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
