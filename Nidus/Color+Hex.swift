//
//  Color+Hex.swift
//  Nidus
//
//  Parses the `cover.tint` hex strings from nidus.json into SwiftUI Colors.
//

import SwiftUI

extension Color {
    /// Creates a Color from a hex string like "#3A5BFF" or "3A5BFF". Falls back to a soft blue.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            self = Color(red: 0.23, green: 0.36, blue: 1.0) // #3A5BFF
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
