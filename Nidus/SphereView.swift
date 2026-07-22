//
//  SphereView.swift
//  Nidus
//
//  Procedural glass sphere for projects and disciplines in the Greeting Panel
//  (GUI greeting spec §5). Soft white glass with a subtle highlight and a graphite icon;
//  disciplines carry a gentle tint, the "New" object is a dashed outline. Default visual
//  until the user supplies custom assets.
//

import SwiftUI

struct SphereView: View {
    enum Style: Equatable {
        case neutral          // white glass (recent projects)
        case tinted(Color)    // subtle colored glass (disciplines)
        case add              // dashed outline ("New")
    }

    let label: String
    var icon: String?
    var style: Style = .neutral
    var diameter: CGFloat = 72
    var folderURL: URL? = nil
    var monochrome: Bool = false
    /// A small pin after the name marks a pinned/anchored project.
    var pinned: Bool = false

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                background
                if let icon {
                    ProjectGlyph(icon: icon, size: diameter,
                                 folderURL: folderURL, monochrome: monochrome)
                }
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(hovering ? 1.06 : 1.0)
            .offset(y: hovering ? -3 : 0)
            .shadow(color: .white.opacity(hovering ? 0.3 : 0), radius: hovering ? 11 : 0) // glow only on hover
            .animation(.spring(response: 0.34, dampingFraction: 0.6), value: hovering) // sticky
            .onHover { hovering = $0 }

            // Up to two lines so a real project name fits ("Brulee Iterations" wraps instead of
            // truncating). reservesSpace keeps every sphere the same height → circles stay aligned.
            // A pinned project gets a small accent pin appended to its name.
            (Text(label).foregroundColor(.secondary)
             + (pinned ? Text("  \(Image(systemName: "pin.fill"))").font(.caption2).foregroundColor(.accentColor)
                       : Text("")))
                .font(.subheadline)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
        }
        .frame(width: diameter + 18)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .add:
            Circle()
                .strokeBorder(.secondary.opacity(0.45),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        case .neutral:
            glass(tint: nil)
        case .tinted(let color):
            glass(tint: color)
        }
    }

    /// Almost fully transparent: the circle is read only by its faint edge + a little glare.
    /// No whitish frost (per design — the icon carries the contrast).
    private func glass(tint: Color?) -> some View {
        Circle()
            .fill(.clear)
            .overlay(highlight)
            .overlay(Circle().strokeBorder(.white.opacity(hovering ? 0.55 : 0.3), lineWidth: 1))
            .clipShape(Circle())
    }

    /// A small top glare arc so the transparent circle still catches the light.
    private var highlight: some View {
        Circle()
            .trim(from: 0.0, to: 0.5)
            .fill(LinearGradient(colors: [.white.opacity(0.5), .clear],
                                 startPoint: .top, endPoint: .center))
            .blur(radius: 4)
            .padding(diameter * 0.12)
    }
}
