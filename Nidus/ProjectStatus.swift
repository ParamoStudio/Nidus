//
//  ProjectStatus.swift
//  Nidus
//
//  A project's lifecycle tag. Stored in nidus.json as a plain string on `Project.status` (an internal
//  tag, never a folder — so it doesn't force a discipline folder per status). Only `active` projects
//  show in the sidebar's working list; completed/archived/deprecated live in the collapsible archive.
//  `deprecated` is the only state that unlocks permanent deletion.
//

import SwiftUI

enum ProjectStatus: String, CaseIterable, Identifiable, Sendable {
    case active, completed, archived, deprecated

    var id: String { rawValue }

    /// Read a project's stored string tolerantly — nil / unknown → active.
    init(_ raw: String?) {
        self = raw.flatMap(ProjectStatus.init(rawValue:)) ?? .active
    }

    /// The string to persist (active is the default → nil, keeps nidus.json clean).
    var stored: String? { self == .active ? nil : rawValue }

    var label: String {
        switch self {
        case .active:     return "Active"
        case .completed:  return "Completed"
        case .archived:   return "Archived"
        case .deprecated: return "Deprecated"
        }
    }

    /// A short line for the status pill / picker, hinting when to use it.
    var hint: String {
        switch self {
        case .active:     return "Being worked on now"
        case .completed:  return "Finished"
        case .archived:   return "On hold or shelved"
        case .deprecated: return "Abandoned — can be deleted"
        }
    }

    var icon: String {
        switch self {
        case .active:     return "circle.fill"
        case .completed:  return "checkmark.circle.fill"
        case .archived:   return "archivebox.fill"
        case .deprecated: return "xmark.circle.fill"
        }
    }

    /// The dot colour used in the sidebar / search results (same idea as Event Log's type dots).
    var color: Color {
        switch self {
        case .active:     return .green
        case .completed:  return .accentColor
        case .archived:   return .secondary
        case .deprecated: return .red
        }
    }
}
