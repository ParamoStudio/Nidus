//
//  ToolSize.swift
//  Nidus
//
//  The three allowed tool sizes in the 5×2 grid (Blueprint §3.2, GUI workspace §6.1).
//  Stored in nidus.json as "1x1" | "1x2" | "2x2".
//

import Foundation

enum ToolSize: String, Codable, Sendable, CaseIterable {
    case small = "1x1"    // square
    case wide = "2x1"     // wide rectangle
    case medium = "1x2"   // tall rectangle (a full column)
    case large = "2x2"    // big square

    var columns: Int { (self == .wide || self == .large) ? 2 : 1 }
    var rows: Int { (self == .small || self == .wide) ? 1 : 2 }
}

extension ToolSlot {
    var toolSize: ToolSize { ToolSize(rawValue: size) ?? .small }
}
