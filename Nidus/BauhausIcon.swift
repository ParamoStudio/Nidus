//
//  BauhausIcon.swift
//  Nidus
//
//  ~20 procedurally drawn Bauhaus / brutalist project glyphs — clean monochrome vectors (no asset
//  files), high contrast (near-black in light / near-white in dark) so they read on the transparent
//  icon circles. Picked from the new-project icon picker; stored as "bauhaus:<n>".
//

import SwiftUI

struct BauhausIcon: View {
    let index: Int
    @Environment(\.colorScheme) private var scheme

    static let count = 14

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let ox = (size.width - s) / 2, oy = (size.height - s) / 2
            let shade = GraphicsContext.Shading.color(scheme == .dark ? .white.opacity(0.92)
                                                                       : .black.opacity(0.82))
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
            }
            let lw = s * 0.13
            let cap = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)

            func fill(_ p: Path, eo: Bool = false) {
                ctx.fill(p, with: shade, style: FillStyle(eoFill: eo))
            }
            func stroke(_ p: Path) { ctx.stroke(p, with: shade, style: cap) }
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: box(cx - r, cy - r, r * 2, r * 2))
            }

            switch index % Self.count {
            case 0: // ring
                var p = circle(0.5, 0.5, 0.36); p.addPath(circle(0.5, 0.5, 0.19)); fill(p, eo: true)
            case 1: // dome / half circle
                var p = Path(); p.addArc(center: pt(0.5, 0.66), radius: 0.37 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false); p.closeSubpath(); fill(p)
            case 2: // crescent
                var p = circle(0.5, 0.5, 0.37); p.addPath(circle(0.66, 0.41, 0.33)); fill(p, eo: true)
            case 3: // leaf (vesica)
                var p = Path(); p.move(to: pt(0.22, 0.78)); p.addQuadCurve(to: pt(0.78, 0.22), control: pt(0.82, 0.82)); p.addQuadCurve(to: pt(0.22, 0.78), control: pt(0.18, 0.18)); fill(p)
            case 4: // quatrefoil (4 round petals)
                var p = Path(); for a in stride(from: 0.0, to: 360.0, by: 90) { p.addPath(circle(0.5 + CGFloat(cos(a * .pi/180)) * 0.2, 0.5 + CGFloat(sin(a * .pi/180)) * 0.2, 0.25)) }; fill(p)
            case 5: // 6-petal flower
                var p = circle(0.5, 0.5, 0.17); for a in stride(from: 0.0, to: 360.0, by: 60) { p.addPath(circle(0.5 + CGFloat(cos(a * .pi/180)) * 0.27, 0.5 + CGFloat(sin(a * .pi/180)) * 0.27, 0.17)) }; fill(p)
            case 6: // peanut (two merged circles)
                var p = circle(0.35, 0.5, 0.27); p.addPath(circle(0.65, 0.5, 0.27)); fill(p)
            case 7: // sparkle (4-point, concave)
                var p = Path(); p.move(to: pt(0.5, 0.08)); p.addQuadCurve(to: pt(0.92, 0.5), control: pt(0.5, 0.5)); p.addQuadCurve(to: pt(0.5, 0.92), control: pt(0.5, 0.5)); p.addQuadCurve(to: pt(0.08, 0.5), control: pt(0.5, 0.5)); p.addQuadCurve(to: pt(0.5, 0.08), control: pt(0.5, 0.5)); p.closeSubpath(); fill(p)
            case 8: // teardrop
                var p = Path(); p.move(to: pt(0.5, 0.1)); p.addQuadCurve(to: pt(0.82, 0.62), control: pt(0.82, 0.28)); p.addArc(center: pt(0.5, 0.62), radius: 0.32 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false); p.addQuadCurve(to: pt(0.5, 0.1), control: pt(0.18, 0.28)); p.closeSubpath(); fill(p)
            case 9: // target (two rings)
                var p = Path(); p.addPath(circle(0.5, 0.5, 0.37)); p.addPath(circle(0.5, 0.5, 0.28)); fill(p, eo: true); fill(circle(0.5, 0.5, 0.13))
            case 10: // pill / stadium
                fill(Path(roundedRect: box(0.14, 0.37, 0.72, 0.26), cornerRadius: 0.13 * s, style: .continuous))
            case 11: // three-blob cluster
                var p = circle(0.5, 0.34, 0.23); p.addPath(circle(0.34, 0.63, 0.23)); p.addPath(circle(0.66, 0.63, 0.23)); fill(p)
            case 12: // wave (rounded)
                var p = Path(); p.move(to: pt(0.13, 0.5)); p.addQuadCurve(to: pt(0.5, 0.5), control: pt(0.31, 0.22)); p.addQuadCurve(to: pt(0.87, 0.5), control: pt(0.69, 0.78)); stroke(p)
            default: // 13: tall ellipse
                fill(Path(ellipseIn: box(0.3, 0.12, 0.4, 0.76)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
