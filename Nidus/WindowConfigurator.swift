//
//  WindowConfigurator.swift
//  Nidus
//
//  Makes the window behave like a floating Spotlight-style panel while in the Greeting state,
//  and expand into a regular resizable window when a project is open (GUI greeting §1, §12).
//
//  macOS only: on iPad there are no floating panels, so this is a no-op and the Greeting
//  content is simply centered within the full-screen scene.
//

import SwiftUI

#if os(macOS)
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    /// `true` for the small floating panels (vault picker + greeting); `false` for the workspace.
    var isPanel: Bool
    /// The fixed panel size for the current panel state (vault picker is smaller than greeting).
    /// We only ever set this on a discrete state change (non-animated) — never animate a
    /// SwiftUI-hosted window's frame (that crashes in NSHostingView.updateAnimatedWindowSize).
    var panelSize: CGSize = CGSize(width: 360, height: 600)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // A brand-new window is born at whatever size macOS hands it (often the large workspace size of
        // the frontmost window) and paints ONE frame before we can resize it — a jarring flash of a huge
        // Greeting. Hide it the instant we can touch it, so we "resolve, then show": it stays invisible
        // until sized+centered below, then fades in.
        if !context.coordinator.didReveal, let w = nsView.window { w.alphaValue = 0 }

        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if !context.coordinator.didReveal { window.alphaValue = 0 }   // belt-and-braces if the sync pass missed

            // Nidus never opens full-screen (the Greeting is a small panel). If macOS restored
            // a previous full-screen state, leave it; and don't persist window state across runs.
            if !context.coordinator.didInitialSetup {
                context.coordinator.didInitialSetup = true
                window.isRestorable = false
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }

            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // Only the floating Greeting panel is moved by dragging its background; in the
            // Workspace this must be off so tiles can be dragged in Customize Mode.
            window.isMovableByWindowBackground = isPanel
            window.isOpaque = false
            window.backgroundColor = .clear
            window.standardWindowButton(.zoomButton)?.isHidden = isPanel
            window.standardWindowButton(.miniaturizeButton)?.isHidden = isPanel

            window.contentMinSize = isPanel ? panelSize : NSSize(width: 1240, height: 820)

            let stateChanged = context.coordinator.lastIsPanel != isPanel
            context.coordinator.lastIsPanel = isPanel

            if isPanel {
                if stateChanged {
                    window.styleMask.remove(.resizable)
                    window.level = .floating
                    context.coordinator.removeWordmark()
                }
                // Resize/recenter on entering the panel OR when the panel size changes
                // (vault picker ↔ greeting) — a plain, non-animated setContentSize is safe.
                if stateChanged || context.coordinator.lastPanelSize != panelSize {
                    context.coordinator.lastPanelSize = panelSize
                    window.setContentSize(panelSize)
                    window.center()
                }
            } else if stateChanged {
                window.styleMask.insert(.resizable)
                window.level = .normal
                window.setContentSize(NSSize(width: 1320, height: 880))
                context.coordinator.addWordmark(to: window)
                window.center()
            }

            // Now the window is at its correct size + position — reveal it (once) with a soft fade, on
            // the NEXT runloop so the resized frame is committed before it becomes visible (no jump).
            if !context.coordinator.didReveal {
                context.coordinator.didReveal = true
                DispatchQueue.main.async {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.22
                        window.animator().alphaValue = 1
                    }
                }
            }
        }
    }

    final class Coordinator {
        var lastIsPanel: Bool?
        var lastPanelSize: CGSize?
        var didInitialSetup = false
        var didReveal = false           // window stays alpha 0 until first sized+centered, then fades in
        private var wordmark: NSTitlebarAccessoryViewController?

        /// The "NIDUS" wordmark, anchored to the right of the (invisible) title bar.
        func addWordmark(to window: NSWindow) {
            guard wordmark == nil else { return }
            let label = Text("NIDUS")
                .font(.caption2.weight(.bold))
                .tracking(2.5)
                .foregroundStyle(.secondary)
                .padding(.trailing, 14)
            let host = NSHostingView(rootView: label)
            host.frame = NSRect(x: 0, y: 0, width: 76, height: 22)
            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = host
            accessory.layoutAttribute = .trailing
            window.addTitlebarAccessoryViewController(accessory)
            wordmark = accessory
        }

        func removeWordmark() {
            wordmark?.removeFromParent()
            wordmark = nil
        }
    }
}

#else

/// iPad: no floating-panel concept. Render nothing.
struct WindowConfigurator: View {
    var isPanel: Bool
    var panelSize: CGSize = CGSize(width: 360, height: 600)
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}

#endif
