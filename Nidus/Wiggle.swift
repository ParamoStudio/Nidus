//
//  Wiggle.swift
//  Nidus
//
//  Customize Mode affordance. Calm, focused ethos (Blueprint Apéndice A): not an anxious
//  side-to-side dance — a soft, slow levitation, each tile gently breathing on its own phase.
//  `kick` lets the caller restart the animation after a layout change (e.g. a move), which can
//  otherwise interrupt the repeating animation.
//

import SwiftUI

private struct Levitate: ViewModifier {
    let active: Bool
    let kick: Int
    @State private var up = false
    @State private var phase = Double.random(in: 0...0.9)

    func body(content: Content) -> some View {
        content
            .offset(y: active ? (up ? -3 : 3) : 0)
            .scaleEffect(active ? (up ? 1.004 : 0.998) : 1)
            .animation(active
                       ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(phase)
                       : .easeOut(duration: 0.35),
                       value: up)
            .onChange(of: active) { _, now in up = now }
            .onChange(of: kick) { _, _ in restart() }
            .onAppear { if active { up = true } }
    }

    /// Re-establish the repeating animation after an interruption (move/commit rebuild).
    private func restart() {
        guard active else { return }
        up = false
        DispatchQueue.main.async { up = true }
    }
}

extension View {
    /// Soft, slow levitation used in Customize Mode. Bump `kick` to restart it after a move.
    func levitate(_ active: Bool, kick: Int = 0) -> some View {
        modifier(Levitate(active: active, kick: kick))
    }
}
