//
//  CardDragController.swift
//  Nidus
//
//  Custom card drag — SwiftUI's `.draggable`/`.dropDestination` didn't deliver drops in the nested
//  grid (and always shows a translucent "ghost", which is visual noise we don't want). Instead the
//  REAL card lifts and follows the cursor; on release we hit-test the cursor against each tool's
//  frame and move the card's Markdown block into the tool underneath. Moving data between `.md`s is
//  already solved (`model.moveCard`); this is just a calmer interaction layer.
//

import SwiftUI

/// A tool tile's drop area: its `.md` + its frame in the shared "workspace" coordinate space.
struct ToolFrameInfo: Equatable {
    let fileURL: URL?
    let toolID: String
    let frame: CGRect
}

struct ToolFramePreferenceKey: PreferenceKey {
    static var defaultValue: [ToolFrameInfo] = []
    static func reduce(value: inout [ToolFrameInfo], nextValue: () -> [ToolFrameInfo]) {
        value += nextValue()
    }
}

@Observable
final class CardDragController {
    struct Dragging: Equatable {
        let card: Card
        let sourceFile: URL
        let sourceTool: String
        let folderURL: URL?
        var location: CGPoint
    }

    /// Enough to open the hovered card from a keyboard shortcut (Space).
    struct HoverInfo: Equatable {
        let card: Card
        let fileURL: URL?
        let folderURL: URL?
        let toolIcon: String
        let toolName: String
    }
    /// The card the cursor is over right now (only one at a time → Space opens it unambiguously).
    var hovered: HoverInfo?

    /// The card currently being dragged (nil when idle).
    var dragging: Dragging?
    /// Drop areas reported by the tool tiles.
    var frames: [ToolFrameInfo] = []
    /// True while a full-window overlay (an expanded tool / card detail) is up: dragging inside it must
    /// NOT target the workspace tools behind it (they're invisible to the user). Set by WorkspaceView.
    var overlayActive = false
    /// The tool file under the cursor right now (a different tool than the source) — for highlight.
    private(set) var targetFile: URL?

    func begin(card: Card, sourceFile: URL, sourceTool: String, folderURL: URL?, at point: CGPoint) {
        dragging = Dragging(card: card, sourceFile: sourceFile, sourceTool: sourceTool,
                            folderURL: folderURL, location: point)
        recomputeTarget()
    }

    func move(to point: CGPoint) {
        guard dragging != nil else { return }
        dragging?.location = point
        recomputeTarget()
    }

    /// On release: if the cursor is over a different tool, move the card there.
    @MainActor func drop(model: NidusModel) {
        if let d = dragging, let target = targetFile {
            model.moveCard(id: d.card.id, from: d.sourceFile, to: target, origin: d.sourceTool)
        }
        dragging = nil
        targetFile = nil
    }

    private func recomputeTarget() {
        guard let d = dragging, !overlayActive else { targetFile = nil; return }
        targetFile = frames.first { info in
            guard let f = info.fileURL else { return false }
            return f.standardizedFileURL != d.sourceFile.standardizedFileURL && info.frame.contains(d.location)
        }?.fileURL
    }
}
