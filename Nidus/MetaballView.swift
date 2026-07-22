//
//  MetaballView.swift
//  Nidus
//
//  A LIVING procedural "metaball" project icon — blobs orbit, drift, merge and split with a gooey
//  viscosity (blurred circles fused by an alpha threshold). Deterministic shape from a seed, but
//  always in gentle motion (TimelineView). High contrast so it reads on the transparent circles.
//
//  A project stores its icon as either an SF Symbol name or "metaball:<seed>". `ProjectGlyph`
//  renders whichever it is, so every place that shows a project icon stays consistent.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MetaballView: View {
    let seed: Int
    /// "avatar" mode (the welcome panel hero): more blobs, livelier, more segregated — a Siri-like
    /// sense of being alive. Project glyphs keep the calmer default.
    var avatar: Bool = false
    /// If set, the mass blooms outward FROM THE CENTRE (from nothing to full size, agglomerating in
    /// place) starting at this instant; once the duration elapses it settles into the normal living
    /// motion. Nil = already composed (the steady living state).
    var introStart: Date? = nil
    var introDuration: Double = 1.5
    @Environment(\.colorScheme) private var scheme

    private struct Blob {
        var orbit: CGFloat   // orbit radius (normalised)
        var speed: Double    // angular speed (rad/s)
        var phase: Double
        var yFreq: Double    // slightly different vertical frequency → organic, non-circular paths
        var size: CGFloat
        var pulse: CGFloat   // size breathing
    }

    private var centralSize: CGFloat {
        var rng = SeededGenerator(seed: seed)
        return CGFloat.random(in: 0.15...0.19, using: &rng)
    }

    /// Few, sizeable blobs that swing FAR out and back — so they read as distinct masses that the
    /// viscosity stretches into necks, then merge and separate again (per the reference). In avatar
    /// mode there are more of them, faster and more segregated, so it feels noticeably more alive.
    private var satellites: [Blob] {
        var rng = SeededGenerator(seed: seed &+ 1)
        let count = avatar ? Int.random(in: 3...4, using: &rng) : Int.random(in: 2...3, using: &rng)
        return (0..<count).map { _ in
            Blob(orbit: CGFloat.random(in: avatar ? 0.22...0.36 : 0.20...0.38, using: &rng),
                 speed: Double.random(in: avatar ? 0.30...0.70 : 0.18...0.50, using: &rng) * (Bool.random(using: &rng) ? 1 : -1),
                 phase: Double.random(in: 0..<(2 * .pi), using: &rng),
                 yFreq: Double.random(in: 0.7...1.3, using: &rng),
                 size: CGFloat.random(in: avatar ? 0.10...0.14 : 0.10...0.16, using: &rng),
                 pulse: CGFloat.random(in: avatar ? 0.03...0.06 : 0.0...0.04, using: &rng))
        }
    }

    private var color: Color { scheme == .dark ? .white.opacity(0.92) : .black.opacity(0.82) }

    /// Compose progress 0→1 (smoothstepped). 1 when not playing an intro.
    private func composeProgress(now: Date) -> CGFloat {
        guard let introStart else { return 1 }
        let e = now.timeIntervalSince(introStart)
        if e <= 0 { return 0 }
        if e >= introDuration { return 1 }
        let x = CGFloat(e / introDuration)
        return x * x * (3 - 2 * x)
    }

    var body: some View {
        let sats = satellites
        let central = centralSize
        let isAvatar = avatar
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date
            let t = now.timeIntervalSinceReferenceDate
            let p = composeProgress(now: now)
            Canvas { context, size in
                let s = min(size.width, size.height)
                // blur (applied to the circles) then alpha threshold → one gooey silhouette
                context.addFilter(.alphaThreshold(min: 0.5, color: color))
                context.addFilter(.blur(radius: s * 0.095)) // a touch gooier → visible necks/stretch
                context.drawLayer { layer in
                    // A subtle whole-body breath in avatar mode → "alive / listening" feel.
                    let breath: CGFloat = isAvatar ? 1 + 0.03 * CGFloat(sin(t * 0.9)) : 1
                    // central mass, drifting so it never feels frozen; grows in during the compose.
                    let cx = 0.5 + 0.05 * CGFloat(cos(t * 0.6)) * breath
                    let cy = 0.5 + 0.05 * CGFloat(sin(t * 0.5)) * breath
                    // Compose: bloom from nothing at the centre outward to full size — orbit and
                    // radius both scale with p, so the mass agglomerates in place and never reaches
                    // past its steady orbit (no edge clipping, unlike flying in from the sides).
                    fill(layer, x: cx, y: cy, r: central * p, in: size, s: s)
                    for b in sats {
                        let ox = CGFloat(cos(b.speed * t + b.phase)) * b.orbit * p
                        let oy = CGFloat(sin(b.speed * b.yFreq * t + b.phase)) * b.orbit * p
                        let x = 0.5 + ox * breath
                        let y = 0.5 + oy * breath
                        let r = (b.size + b.pulse * CGFloat(sin(t * 0.8 + b.phase))) * p
                        fill(layer, x: x, y: y, r: r, in: size, s: s)
                    }
                }
            }
        }
    }

    private func fill(_ layer: GraphicsContext, x: CGFloat, y: CGFloat, r: CGFloat,
                      in size: CGSize, s: CGFloat) {
        let radius = r * s
        let rect = CGRect(x: x * size.width - radius, y: y * size.height - radius,
                          width: radius * 2, height: radius * 2)
        layer.fill(Path(ellipseIn: rect), with: .color(.white))
    }
}

/// A faint, slowly-pulsing ring — gives the icon circles a sense of quiet activity/presence.
struct GlowingRing: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let p = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 1.3)
            Circle()
                .strokeBorder(.white.opacity(0.22 + 0.22 * p), lineWidth: 1)
                .shadow(color: .white.opacity(0.10 + 0.18 * p), radius: 3 + 4 * p)
        }
    }
}

/// Renders a project icon — metaball ("metaball:<seed>"), Bauhaus glyph ("bauhaus:<n>"), imported
/// image ("image", loaded from `folderURL`/.nidus-icon.png), or an SF Symbol. Imported images show
/// in colour in the Workspace and `monochrome` (greyscale) in the Greeting.
struct ProjectGlyph: View {
    let icon: String?
    /// The full circle box. Imported images FILL it; metaball/bauhaus sit inset (when `circled`).
    let size: CGFloat
    var folderURL: URL? = nil
    var monochrome: Bool = false
    /// True when there's a surrounding circle (greeting/workspace/add): inset glyphs, fill images.
    var circled: Bool = true

    static let imageFileName = ".nidus-icon.png"

    private var glyphSize: CGFloat { size * (circled ? 0.72 : 1.0) }
    /// Imported/built-in logos are usually full-bleed to their box, so their corners poke out of the
    /// circle at the procedural-glyph inset. Inset them a touch more to sit comfortably inside.
    private var logoGlyphSize: CGFloat { size * (circled ? 0.58 : 1.0) }

    var body: some View {
        ZStack {
            if icon == "image", let image = importedImage {
                // Treated as a TEMPLATE: the image's silhouette, tinted to .primary (white in dark,
                // black in light) so a custom logo integrates exactly like the built-in glyphs.
                image
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
                    .frame(width: logoGlyphSize, height: logoGlyphSize)
            } else if let seed = ProjectGlyph.metaballSeed(icon) {
                MetaballView(seed: seed).frame(width: glyphSize, height: glyphSize)
            } else if let n = ProjectGlyph.bauhausIndex(icon) {
                BauhausIcon(index: n).frame(width: glyphSize, height: glyphSize)
            } else if let name = BuiltInIcons.name(icon) {
                Image(name).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary).frame(width: logoGlyphSize, height: logoGlyphSize)
            } else {
                Image(systemName: icon ?? Project.defaultIcon)
                    .font(.system(size: size * (circled ? 0.42 : 0.5), weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
    }

    private var importedImage: Image? {
        guard let url = folderURL?.appendingPathComponent(Self.imageFileName) else { return nil }
        return nidusLoadImage(at: url)
    }

    static func metaballSeed(_ icon: String?) -> Int? {
        guard let icon, icon.hasPrefix("metaball:") else { return nil }
        return Int(icon.dropFirst("metaball:".count))
    }
    static func bauhausIndex(_ icon: String?) -> Int? {
        guard let icon, icon.hasPrefix("bauhaus:") else { return nil }
        return Int(icon.dropFirst("bauhaus:".count))
    }
}

/// Load an image file as a SwiftUI Image, cross-platform.
func nidusLoadImage(at url: URL) -> Image? {
    #if os(macOS)
    guard let ns = NSImage(contentsOf: url) else { return nil }
    return Image(nsImage: ns)
    #else
    guard let ui = UIImage(contentsOfFile: url.path) else { return nil }
    return Image(uiImage: ui)
    #endif
}

/// Tiny deterministic RNG (SplitMix64) so a seed always yields the same metaball.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
