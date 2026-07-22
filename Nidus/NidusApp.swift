//
//  NidusApp.swift
//  Nidus
//
//  Entry point. No SwiftData, no database: the filesystem is the single source of truth (§9.3).
//  One window = one project; ⌘N opens a new window (its own Greeting Panel), ⌘W closes it.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct NidusApp: App {
    /// Shared app-wide state (vault + config). Project selection is per-window.
    @State private var model = NidusModel()
    @State private var theme = ThemeController()
    /// Phone pairing + capture sync (see PhoneBridge.swift). App-wide: one pairing per vault/device.
    @State private var bridge = PhoneBridge()

    init() {
        #if os(macOS)
        // One project = one WINDOW, never a tab. Without this, ⌘N on a maximized window makes macOS
        // merge the new window in as a TAB (shrinking the existing one) — the opposite of what we want:
        // separate, independently-sizable windows so several projects can be open side by side.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootWindowView()
                .environment(model)
                .environment(theme)
                .environment(bridge)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        // New windows (⌘N → a Greeting) are born at the panel size, so they don't flash the large
        // workspace size (inherited from the last window) before WindowConfigurator shrinks them.
        .defaultSize(width: 360, height: 600)
        #endif
    }
}
