//
//  IconButton.swift
//  Nidus
//
//  Round, text-less control with Apple-like feedback: hover reaction (lift + glow) and a
//  haptic tap on press. Used for the top-bar controls (Customize, light/dark) across screens.
//

import SwiftUI

struct IconButton: View {
    let systemName: String
    var active: Bool = false
    var help: LocalizedStringKey = ""
    let action: () -> Void

    @Environment(ThemeController.self) private var theme
    @State private var hovering = false

    /// Drive the glyph colour off the app's OWN light/dark truth, not `.secondary`. The glass buttons
    /// sit over a desktop-blur background, so a semantic colour can end up sampling the wrong scheme
    /// and never visibly flip; this guarantees a light glyph on dark and a dark one on light.
    private var idleColor: Color {
        theme.isDark ? Color.white.opacity(0.78) : Color.black.opacity(0.62)
    }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : idleColor)
                .frame(width: 34, height: 34)
                .contentShape(Circle()) // the whole circle is the hit target, not just the glyph
        }
        .buttonStyle(.plain)
        // Native Liquid Glass: interactive() gives the live hover/press response.
        .glassEffect((active ? Glass.regular.tint(.accentColor.opacity(0.4)) : .regular).interactive(),
                     in: Circle())
        // Explicit hover signal (availability), on top of the glass reaction.
        .scaleEffect(hovering ? 1.12 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .help(help)
        // A URL-opening button mutates no state, so (unlike the theme/customize toggles) it never
        // re-renders after a click — and opening the browser steals focus, stranding the glass
        // highlight until a hover. Rebuilding on focus-state change clears it, the same way the
        // stateful buttons clear for free.
        .rebuildOnFocusChange()
    }
}

private extension View {
    /// macOS: rebuild the view whenever the window's active/focus state flips, so a Liquid Glass
    /// interactive highlight can't stay stranded after the app loses focus. No-op on iOS.
    @ViewBuilder func rebuildOnFocusChange() -> some View {
        #if os(macOS)
        modifier(FocusStateRebuild())
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct FocusStateRebuild: ViewModifier {
    @Environment(\.controlActiveState) private var controlActive
    func body(content: Content) -> some View { content.id(controlActive) }
}
#endif

/// Light/dark toggle, app-wide. Triggers the calm wash transition. Shared by Greeting + Workspace.
struct AppearanceToggle: View {
    @Environment(ThemeController.self) private var theme
    var body: some View {
        IconButton(systemName: theme.isDark ? "moon.fill" : "sun.max",
                   help: "Toggle light / dark") {
            theme.toggle()
        }
    }
}
