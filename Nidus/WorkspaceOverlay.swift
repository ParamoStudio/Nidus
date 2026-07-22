//
//  WorkspaceOverlay.swift
//  Nidus
//
//  Presents a translucent detail panel (idea/task notes) over a dimmed, blurred backdrop —
//  an NSPanel-like surface on top, gaussian over the rest. Tools call `present`; the Workspace
//  renders it full-window so it isn't clipped to a tile.
//

import SwiftUI

@MainActor
@Observable
final class WorkspaceOverlay {
    var content: AnyView?

    func present<V: View>(@ViewBuilder _ view: () -> V) {
        content = AnyView(view())
    }

    func dismiss() {
        content = nil
    }
}
