//
//  ToolTileView.swift
//  Nidus
//
//  A tool's tile in the grid. Chrome (title, icon, size) + the tool's body, resolved from the
//  ToolRegistry. In Customize Mode the body is inert and a remove control appears (not Inbox).
//

import SwiftUI

struct ToolTileView: View {
    let slot: ToolSlot
    let context: ToolContext
    var isEditing: Bool = false
    var highlighted: Bool = false
    var levitateKick: Int = 0
    var onRemove: () -> Void = {}
    var onRename: () -> Void = {}
    /// Optional: tapping the tile's title/icon header runs this (e.g. Notebook opens its library).
    var onTitleTap: (() -> Void)? = nil

    private var descriptor: ToolDescriptor { ToolRegistry.descriptor(for: slot.tool) }
    private var removable: Bool { slot.tool != "inbox" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tool identity: icon + name, centered and prominent so it's easy to read at a glance.
            HStack(spacing: 9) {
                Image(systemName: descriptor.icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(slot.name ?? descriptor.defaultName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture { if !isEditing, let onTitleTap { onTitleTap() } }

            descriptor.makeView(context)
                .id(slot.id) // stable identity so the tool keeps its @State across re-renders
                .disabled(isEditing)
                .allowsHitTesting(!isEditing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle()) // the whole container is the drag target in Customize
        .glassCard(frosted: true)
        .overlay(
            RoundedRectangle(cornerRadius: NidusRadius.card, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: isEditing ? 1.5 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NidusRadius.card, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: highlighted ? 2.5 : 0)
                .opacity(highlighted ? 1 : 0)
        )
        .shadow(color: .accentColor.opacity(highlighted ? 0.35 : 0), radius: 14)
        .scaleEffect(isEditing ? 1.01 : (highlighted ? 1.012 : 1.0))
        .levitate(isEditing, kick: levitateKick) // re-kicks after a move so it keeps breathing
        .overlay(alignment: .topTrailing) {
            if isEditing && removable {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(.background))
                }
                .buttonStyle(.plain)
                .padding(8)
                .help("Remove tool")
            }
        }
        .overlay(alignment: .topLeading) {
            if isEditing && removable {
                Button(action: onRename) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(.background))
                }
                .buttonStyle(.plain)
                .padding(8)
                .help("Rename")
            }
        }
    }
}
