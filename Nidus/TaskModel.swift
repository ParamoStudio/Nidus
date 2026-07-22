//
//  TaskModel.swift
//  Nidus
//
//  Task-specific model layered on the universal Card. Tasks reuse the same lossless card (title,
//  notes = subnote, dates, origin), and add three things kept in the card's open `extra` map:
//   • tag ids — pointing at a vault-level bank of shared tags (like disciplines), each with a colour
//   • a deadline — a date + a Day/Week/Month scope (Day is a hard date; Week/Month are soft windows)
//   • a deadline note — free text ("for the review", …)
//  Because everything lives in `extra`, a task stays a plain card that any tool can read and move.
//

import SwiftUI

// MARK: - Tags (shared bank)

/// A reusable tag. Created by typing; shared across every Task Manager (persisted in nidus.json).
struct TaskTag: Codable, Equatable, Identifiable, Sendable, Hashable {
    var id: String     // slug of the name
    var name: String
    var color: Int     // index into TagPalette (0…7)
}

/// The 8 fixed tag colours — no colour picker, just a swatch to pick from. Muted on purpose (calm,
/// not radioactive), while still being 8 distinguishable hues.
enum TagPalette {
    static let count = 8
    static let colors: [Color] = [
        Color(hex: "D06565"), Color(hex: "D08A3E"), Color(hex: "C4A83E"), Color(hex: "5FA971"),
        Color(hex: "5B83C6"), Color(hex: "9576BB"), Color(hex: "8E8E99"), Color(hex: "C87EA4"),
    ]
    static func color(_ i: Int) -> Color { colors[((i % count) + count) % count] }
}

// MARK: - Deadline

enum DeadlineScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

/// A deadline = a date + how strict it is. `.day` is a hard date; `.week`/`.month` are soft windows.
struct TaskDeadline: Equatable, Sendable {
    var date: Date
    var scope: DeadlineScope

    /// A compact label for the card pill, e.g. "Jun 16", "Wk Jun 16", "June".
    var pillText: String {
        switch scope {
        case .day:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .week:
            let start = Calendar.current.startOfWeek(for: date)
            return "Wk " + start.formatted(.dateTime.month(.abbreviated).day())
        case .month:
            return date.formatted(.dateTime.month(.wide))
        }
    }
}

extension Calendar {
    /// Start of the ISO week containing `date`.
    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - Task fields on the universal Card (stored in `extra`, lossless)

extension Card {
    /// Tag ids attached to this task (order preserved).
    var tagIDs: [String] {
        get { (extra["tags"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { extra["tags"] = newValue.isEmpty ? nil : newValue.joined(separator: ",") }
    }

    var deadline: TaskDeadline? {
        get {
            guard let raw = extra["dueScope"], let scope = DeadlineScope(rawValue: raw),
                  let ds = extra["dueDate"], let date = ISO8601DateFormatter().date(from: ds)
            else { return nil }
            return TaskDeadline(date: date, scope: scope)
        }
        set {
            if let nv = newValue {
                extra["dueDate"] = ISO8601DateFormatter().string(from: nv.date)
                extra["dueScope"] = nv.scope.rawValue
            } else {
                extra["dueDate"] = nil
                extra["dueScope"] = nil
            }
        }
    }

    var deadlineNote: String {
        get { extra["dueNote"] ?? "" }
        set { extra["dueNote"] = newValue.isEmpty ? nil : newValue }
    }

    /// Basename of the todo file a completed task came from, so the archive can send it back.
    var originFile: String? {
        get { extra["originFile"] }
        set { extra["originFile"] = newValue }
    }

    /// Display name of the task manager a completed task came from (shown in the archive).
    var originName: String? {
        get { extra["originName"] }
        set { extra["originName"] = newValue }
    }
}

// MARK: - Deadline aggregation (feeds the Deadline Calendar overview)

/// One active task with a deadline, from any task manager in the project.
struct DeadlineEntry: Identifiable {
    let id: String
    let title: String
    let deadline: TaskDeadline
    let listName: String       // which task manager it belongs to
    let colorIndex: Int?       // a single tag's colour; nil when it has none or several (neutral)

    /// Single tag → its colour; none / several → high-contrast neutral (white on dark, black on light).
    var dotColor: Color { colorIndex.map { TagPalette.color($0) } ?? Color.primary }

    /// Date used to order entries (start of the day/week/month it targets).
    var sortDate: Date {
        let cal = Calendar.current
        switch deadline.scope {
        case .day:   return cal.startOfDay(for: deadline.date)
        case .week:  return cal.startOfWeek(for: deadline.date)
        case .month: return cal.date(from: cal.dateComponents([.year, .month], from: deadline.date)) ?? deadline.date
        }
    }

    /// Still relevant if its window hasn't fully passed (a whole week/month counts until it ends).
    func isRelevant(now: Date = Date()) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        switch deadline.scope {
        case .day:
            return cal.startOfDay(for: deadline.date) >= today
        case .week:
            let end = cal.date(byAdding: .day, value: 6, to: cal.startOfWeek(for: deadline.date)) ?? deadline.date
            return cal.startOfDay(for: end) >= today
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: deadline.date)) ?? deadline.date
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? deadline.date
            return cal.startOfDay(for: end) >= today
        }
    }
}

extension NidusModel {
    /// Every deadlined active task across all task managers in a project's grid (the aggregator).
    func deadlineEntries(folderURL: URL?, grid: [ToolSlot]) -> [DeadlineEntry] {
        guard let folderURL else { return [] }
        var out: [DeadlineEntry] = []
        for slot in grid where slot.tool == "task-manager" {
            let todo = slot.files?.first ?? "tasks-todo.md"
            let url = folderURL.appendingPathComponent(todo)
            for card in CardStore.read(from: url) {
                guard let dl = card.deadline else { continue }
                let ids = card.tagIDs
                let colorIndex = ids.count == 1 ? tag(id: ids[0])?.color : nil
                out.append(DeadlineEntry(id: card.id, title: card.title, deadline: dl,
                                         listName: slot.name ?? "Task Manager", colorIndex: colorIndex))
            }
        }
        return out
    }
}
