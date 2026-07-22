//
//  ProjectStatusControls.swift
//  Nidus
//
//  The floating control cluster that appears beside the project's identity card in Customize Mode:
//  a Status pill (active / completed / archived / deprecated), a Fork action, and — only when the
//  project is deprecated — a double-confirmed Delete Permanently. Everything here is non-destructive
//  except that last one.
//

import SwiftUI

struct ProjectStatusControls: View {
    let ref: ProjectRef
    /// Called with the new fork's ref so the window can switch to it.
    let onForked: (ProjectRef) -> Void
    /// Called after a permanent delete (the project is gone → leave the workspace).
    let onDeleted: () -> Void

    @Environment(NidusModel.self) private var model
    @State private var pickingStatus = false
    @State private var confirmingDelete = false

    private var status: ProjectStatus { model.status(for: ref) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusPill
            forkButton
            if status == .deprecated { deleteControl }
        }
        .frame(width: 190, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    // MARK: Status

    private var statusPill: some View {
        Button { pickingStatus.toggle() } label: {
            HStack(spacing: 7) {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text(status.label).font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .popover(isPresented: $pickingStatus, arrowEdge: .bottom) { statusPicker }
    }

    private var statusPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ProjectStatus.allCases) { s in
                Button {
                    model.setStatus(ref, s)
                    pickingStatus = false
                } label: {
                    HStack(spacing: 9) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.label).font(.callout.weight(.medium)).foregroundStyle(.primary)
                            Text(s.hint).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        if s == status { Image(systemName: "checkmark").font(.caption).foregroundStyle(Color.accentColor) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(s == status ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(8)
        .frame(width: 260)
    }

    // MARK: Fork

    private var forkButton: some View {
        Button {
            if let forkRef = model.forkProject(ref) { onForked(forkRef) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.branch").font(.callout)
                Text("Fork project").font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .help("Duplicate this project to explore a new direction")
    }

    // MARK: Delete permanently (double-confirm)

    @ViewBuilder private var deleteControl: some View {
        if confirmingDelete {
            VStack(alignment: .leading, spacing: 6) {
                Text("Delete this project forever? This can't be undone.")
                    .font(.caption2).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Cancel") { confirmingDelete = false }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    Button("Delete permanently") {
                        if model.deleteProjectPermanently(ref) { onDeleted() }
                    }
                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.red.opacity(0.35)))
        } else {
            Button { confirmingDelete = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "trash").font(.callout)
                    Text("Delete permanently").font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 12).frame(height: 34)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }
}
