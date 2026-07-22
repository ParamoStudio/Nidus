//
//  ThemeController.swift
//  Nidus
//
//  Light/dark as a smooth background crossfade — NO full-screen overlay, so elements stay
//  visible the whole time (nothing blacks/whites out). `darkness` (0 light, 1 dark) animates and
//  drives the ambient gradient; the scheme (materials/text) commits once, mid-fade.
//  Persisted locally; never in the vault (Blueprint §9.7).
//

import SwiftUI

@MainActor
@Observable
final class ThemeController {
    private let key = "nidus.appearance.dark"

    private(set) var isDark: Bool
    /// 0 = light, 1 = dark. Animated; drives the ambient background crossfade.
    var darkness: Double

    init() {
        let dark = UserDefaults.standard.bool(forKey: key)
        isDark = dark
        darkness = dark ? 1 : 0
    }

    func toggle() {
        let target = !isDark
        // The tools (native glass + text) can't crossfade between schemes in SwiftUI — they
        // switch instantly. So switch them right at the click (an expected, responsive change),
        // and let the ambient background ease toward the new scheme. No mid-fade mismatch "golpe".
        withAnimation(.easeOut(duration: 0.9)) {
            isDark = target              // tools/text flip now, with the click
            darkness = target ? 1 : 0    // background eases to match
        }
        UserDefaults.standard.set(target, forKey: key)
    }
}
