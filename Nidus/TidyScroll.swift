//
//  TidyScroll.swift
//  Nidus
//
//  A ScrollView without the space-hungry scrollbar. Instead, a very subtle "…" pill at the
//  bottom signals there's more material below (space management matters; bars feel like clutter).
//

import SwiftUI

struct TidyScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var overflowing: Bool { contentHeight > viewportHeight + 1 }

    var body: some View {
        ScrollView {
            // Measure the content directly (no background GeometryReader / preference round-trip,
            // which could double-render the text during layout passes).
            content()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.never)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .overlay(alignment: .bottom) {
            if overflowing {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: overflowing)
    }
}
