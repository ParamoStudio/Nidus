//
//  GlassCompat.swift
//  Nidus
//
//  One binary, two appearances.
//
//  Liquid Glass (`glassEffect`) is macOS 26 only, and macOS 26 is where nearly every Intel Mac stops
//  being invited. Rather than fork the app, every glass surface goes through this shim: on macOS 26 it
//  IS the real thing, and on Sequoia it falls back to a translucent wash with a lit edge.
//
//  `#available` is a RUNTIME check, so a single build serves both — there is no second branch to keep
//  in sync, and no second download to explain.
//
//  What the fallback deliberately does NOT do is imitate glass with a heavy frosted material. Nidus's
//  window is already translucent (`GlassBackground` → NSVisualEffectView, available since 10.14), so
//  the ambient gradient and the blurred desktop still read through; a thick material on top of that
//  reads as a grey slab and weighs more than the content it holds. A thin wash plus an edge keeps the
//  surface subordinate to what's written on it, which is the whole point of the design.
//

import SwiftUI

extension View {
    /// The app's glass surface. `interactive` marks a control (it drives the live hover/press response
    /// on macOS 26; pre-26 the controls carry their own hover effects already). `tint` is the accent
    /// wash worn by active toggles.
    /// `frosted: false` is the Greeting's clearer surface — it asserts itself less than a Workspace card.
    func nidusGlass<S: InsettableShape>(_ shape: S,
                                        interactive: Bool = false,
                                        tint: Color? = nil,
                                        frosted: Bool = true) -> some View {
        modifier(NidusGlass(shape: shape, interactive: interactive, tint: tint, frosted: frosted))
    }
}

struct NidusGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive: Bool = false
    var tint: Color? = nil
    var frosted: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            // Byte for byte what the app did before this shim existed. On a current Mac this is the
            // ONLY path: no environment is read, no extra view is inserted, nothing is approximated.
            let base: Glass = frosted ? .regular : .clear
            let glass = tint.map { base.tint($0) } ?? base
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            content.modifier(LegacyGlass(shape: shape, tint: tint, frosted: frosted))
        }
    }
}

/// The pre-26 half, kept in its own modifier so the macOS 26 path above declares no environment
/// dependency at all — reading the theme there would invalidate every glass surface on a theme
/// change for no reason.
private struct LegacyGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var frosted: Bool = true

    /// Optional on purpose: a view used outside the app's root (a preview, a detached sheet) falls
    /// back to the system scheme rather than crashing on a missing environment object.
    @Environment(ThemeController.self) private var theme: ThemeController?
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { theme?.isDark ?? (scheme == .dark) }

    /// Light needs a much stronger wash: white at 8% over a pale background is invisible.
    private var fill: Color {
        let o = isDark ? 0.08 : 0.55
        return .white.opacity(frosted ? o : o * 0.55)
    }
    private var edge: Color { .white.opacity(isDark ? 0.22 : 0.80) }

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(fill)
                if let tint { shape.fill(tint) }
            }
            // The lit edge is what reads as glass at a glance; without it this is a flat panel.
            .overlay(shape.strokeBorder(edge, lineWidth: 1))
            .clipShape(shape)
    }
}
