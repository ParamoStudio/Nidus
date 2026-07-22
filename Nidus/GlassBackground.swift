//
//  GlassBackground.swift
//  Nidus
//
//  The window's refractive glass surface. On macOS it samples the desktop behind the window
//  (behind-window blending). The Greeting Panel uses strong glass; the Workspace reduces it,
//  since there we read and write and too much translucency hurts focus (GUI workspace §10).
//  On iPad it's a material over the system background.
//

import SwiftUI

#if os(macOS)
import AppKit

struct GlassBackground: NSViewRepresentable {
    /// Reduced glass for the Workspace (more opaque, better legibility).
    var reduced = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }

    private var material: NSVisualEffectView.Material {
        reduced ? .underWindowBackground : .hudWindow
    }
}

#else

struct GlassBackground: View {
    var reduced = false
    var body: some View {
        Rectangle()
            .fill(reduced ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
            .ignoresSafeArea()
    }
}

#endif
