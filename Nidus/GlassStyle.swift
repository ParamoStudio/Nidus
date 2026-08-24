//
//  GlassStyle.swift
//  Nidus
//
//  The glass design language (Blueprint Apéndice A; user render 2026-06-21).
//  Frosted glass surfaces over a contained warm→cool ambient gradient. Workspace = more
//  frosted, Greeting = clearer. Reusable so every surface speaks the same language.
//

import SwiftUI

enum NidusRadius {
    static let card: CGFloat = 20
    static let inner: CGFloat = 14
    static let pill: CGFloat = 10
}

/// A native Liquid Glass surface (macOS/iOS 26+): real refraction and specular edges.
/// Workspace surfaces are `.regular` (more frosted); Greeting surfaces are `.clear` (clearer).
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = NidusRadius.card
    var frosted: Bool = true

    func body(content: Content) -> some View {
        // `frosted` maps to how much the surface asserts itself; see GlassCompat for the pre-26 half.
        content.nidusGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                           frosted: frosted)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = NidusRadius.card, frosted: Bool = true) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, frosted: frosted))
    }
}

/// The app's contained ambient gradient — translucent (the blurred desktop shows through) with a
/// soft blue bloom. It crossfades between light and dark by interpolating on `theme.darkness`,
/// so toggling appearance is a smooth background fade with the content always visible.
struct AmbientBackground: View {
    @Environment(ThemeController.self) private var theme
    /// The Greeting Panel wants a much glassier tint so the (blurred) desktop reads through.
    var reduced: Bool = false

    private let lightStops: [(Double, Double, Double)] = [
        (0.949, 0.937, 0.918), (0.910, 0.918, 0.957), (0.875, 0.894, 0.957)
    ]
    private let darkStops: [(Double, Double, Double)] = [
        (0.098, 0.102, 0.133), (0.078, 0.082, 0.125), (0.102, 0.110, 0.157)
    ]

    var body: some View {
        let t = theme.darkness
        let alpha = reduced ? (0.18 + 0.12 * t) : (0.62 + 0.16 * t)
        LinearGradient(colors: (0..<3).map { mix(lightStops[$0], darkStops[$0], t, alpha: alpha) },
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                RadialGradient(colors: [Color(hex: "#3A5BFF").opacity(0.34 - 0.12 * t), .clear],
                               center: .topTrailing, startRadius: 20, endRadius: 720)
            )
            .overlay(
                RadialGradient(colors: [Color(hex: "#7E96FF").opacity(0.22 - 0.08 * t), .clear],
                               center: UnitPoint(x: 0.45, y: 0.7), startRadius: 20, endRadius: 560)
            )
            .ignoresSafeArea()
    }

    private func mix(_ l: (Double, Double, Double), _ d: (Double, Double, Double),
                     _ t: Double, alpha: Double) -> Color {
        Color(.sRGB, red: l.0 + (d.0 - l.0) * t, green: l.1 + (d.1 - l.1) * t,
              blue: l.2 + (d.2 - l.2) * t, opacity: alpha)
    }
}
