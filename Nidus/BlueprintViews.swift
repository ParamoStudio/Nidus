//
//  BlueprintViews.swift
//  Nidus
//
//  UI for the pinned "Current Blueprint": a small pill in identityCard's top-right corner (mutually
//  exclusive with the Customize-Mode edit pencil — WorkspaceView shows one or the other) that opens a
//  compact panel: pick a template (built-in or imported) → fill it in → read view with a pencil to edit
//  → "Save & Log Update" bumps the version and appends an activity line. See Blueprint.swift for the model.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// The corner pill: a fixed, always-recognizable label — NOT the template name, so it reads as "this is
/// the project's focal point" at a glance regardless of what's inside.
struct BlueprintPill: View {
    let hasContent: Bool
    var label: String = "Project Blueprint"
    let action: () -> Void

    // The pill sits over a desktop-blur backdrop, where a semantic accent-on-tint can wash out in light
    // mode. Drive contrast off the app's OWN light/dark truth (same reason IconButton does).
    @Environment(ThemeController.self) private var theme
    @State private var hover = false

    var body: some View {
        let dark = theme.isDark
        // Dark: a subtle accent tint with accent text (already reads well). Light: a solid accent fill
        // with white text, so it's clearly legible instead of a faint orange-on-white.
        let fill = dark ? Color.accentColor.opacity(hover ? 0.24 : 0.16)
                        : Color.accentColor.opacity(hover ? 1.0 : 0.92)
        let foreground = dark ? Color.accentColor : Color.white
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "scope")
                Text(label).lineLimit(1)
                if hasContent {
                    Circle().fill(foreground).frame(width: 4, height: 4)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(dark ? 0.35 : 0)))
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help("The project's blueprint — its current direction, always a tap away")
    }
}

/// The expanded panel: template picker (no blueprint yet) → read view ↔ edit form. Kept deliberately
/// compact — this is a mental-anchor overview, not another notebook.
struct BlueprintPanel: View {
    let projectFolder: URL
    let vaultURL: URL?
    let onClose: () -> Void

    @State private var blueprint: Blueprint?
    @State private var editing = false
    @State private var draft: [BlueprintField] = []
    @State private var loaded = false
    @State private var customTemplates: [BlueprintTemplate] = []
    @State private var confirmingReset = false
    @State private var confirmingForward = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private let panelWidth: CGFloat = 620
    private let headerChrome: CGFloat = 49
    private let minPanelHeight: CGFloat = 260
    @State private var measuredContent: CGFloat = 0

    var body: some View {
        // Grows to fit its content (picker / read / edit), capped by the window — so a filled-in
        // blueprint occupies what it needs instead of being trapped in a fixed, scrolling box.
        GeometryReader { proxy in
            let maxH = max(minPanelHeight, proxy.size.height - 48)
            let height = min(max(measuredContent + headerChrome, minPanelHeight), maxH)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "scope").font(.title3).foregroundStyle(.secondary)
                    Text("Project Blueprint").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if blueprint != nil {
                        NotebookCircleButton(system: editing ? "checkmark" : "pencil", active: editing) {
                            if editing { save() } else { beginEdit() }
                        }
                    }
                    NotebookCircleButton(system: "xmark", action: onClose)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                Divider().opacity(0.4)
                TidyScroll {
                    content.padding(18)
                }
            }
            .frame(width: panelWidth, height: height)
            .glassCard()
            .background(Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0))
            .background(
                content.padding(18)
                    .frame(width: panelWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredContent = $0 }
                    .hidden().allowsHitTesting(false)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.16), value: measuredContent)
        .onAppear {
            blueprint = BlueprintStore.load(projectFolder: projectFolder)
            if let vaultURL { customTemplates = BlueprintTemplateStore.customTemplates(vault: vaultURL) }
            loaded = true
        }
    }

    @ViewBuilder private var content: some View {
        if !loaded {
            EmptyView()
        } else if let bp = blueprint, !editing {
            readView(bp)
        } else if blueprint != nil {
            editForm
        } else {
            templatePicker
        }
    }

    // MARK: Template picker

    private var allTemplates: [BlueprintTemplate] { BlueprintTemplate.builtIns + customTemplates }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's this project actually making — given everything you know right now?")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(allTemplates) { t in
                    Button { choose(t) } label: { templateTile(t) }
                        .buttonStyle(.plain)
                }
                #if os(macOS)
                Button { importTemplateFile() } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "square.and.arrow.down").font(.title3).foregroundStyle(.secondary)
                        Text("Import a template…").font(.subheadline.weight(.semibold))
                        Text("A .md: # Name, then one ## Field per line").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                #endif
            }
        }
    }

    private func templateTile(_ t: BlueprintTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: t.icon).font(.title3).foregroundStyle(Color.accentColor)
            Text(t.name).font(.subheadline.weight(.semibold))
            Text(t.hint).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func choose(_ t: BlueprintTemplate) {
        blueprint = Blueprint.fresh(template: t)
        if let blueprint { BlueprintStore.save(blueprint, projectFolder: projectFolder) }
        beginEdit()
    }

    #if os(macOS)
    /// `.fileImporter` doesn't fire reliably on a view presented through `WorkspaceOverlay`'s `AnyView`
    /// (same issue CardViews.swift hit with micro-tool import) — NSOpenPanel sidesteps it.
    private func importTemplateFile() {
        guard let vaultURL else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url,
                  let t = BlueprintTemplateStore.importTemplate(from: url, vault: vaultURL) else { return }
            customTemplates = BlueprintTemplateStore.customTemplates(vault: vaultURL)
            choose(t)
        }
    }
    #endif

    // MARK: Read view

    private func readView(_ bp: Blueprint) -> some View {
        // A calm, centered "flyer": a reminder of what this is, the template name, then each field as
        // LABEL · separator · value-card, all centered. It should read as "this is your focus", not a form.
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("YOUR CURRENT DIRECTION")
                    .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.tertiary)
                Text("What this project is working toward, right now — the focal point behind the day-to-day.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(bp.templateName).font(.subheadline.weight(.semibold))
                    Text("v\(bp.version)").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .padding(.top, 2)
                Text("Approved \(bp.approvedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)

            let visible = bp.fields.filter { $0.included && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if visible.isEmpty {
                Text("Nothing filled in yet — tap the pencil.").font(.caption).foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 18) {
                    ForEach(visible) { f in
                        VStack(spacing: 8) {
                            Text(f.label.uppercased())
                                .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 34, height: 1)
                            Text(f.value)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            if bp.previous != nil || bp.activity.count > 1 {
                VStack(spacing: 8) {
                    if let prev = bp.previous {
                        if bp.swapGoesForward {
                            // A HIGHER version number is "forward" (leaving the version you deliberately
                            // reverted to) → gets a confirmation, unlike an instant revert.
                            Button("Return to v\(prev.version) (current)") { confirmingForward = true }
                                .buttonStyle(.plain).font(.caption2).foregroundStyle(Color.accentColor)
                                .confirmationDialog("Return to v\(prev.version)? That becomes the active version again.",
                                                    isPresented: $confirmingForward, titleVisibility: .visible) {
                                    Button("Return to v\(prev.version)") { swap() }
                                    Button("Cancel", role: .cancel) {}
                                }
                        } else {
                            Button("Revert to v\(prev.version)") { swap() }
                                .buttonStyle(.plain).font(.caption2).foregroundStyle(Color.accentColor)
                        }
                    }
                    if bp.activity.count > 1 {
                        ForEach(Array(bp.activity.reversed().prefix(4).enumerated()), id: \.offset) { _, a in
                            Text("v\(a.version) · \(a.note) · \(a.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Edit form

    private func beginEdit() {
        draft = blueprint?.fields ?? []
        confirmingReset = false
        editing = true
    }

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(draft.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Button {
                                draft[i].included.toggle()
                            } label: {
                                Image(systemName: draft[i].included ? "checkmark.square.fill" : "square")
                                    .font(.caption2).foregroundStyle(draft[i].included ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(draft[i].included ? "Included in the overview — tap to annul" : "Annulled — won't show in the read view")
                            Text(draft[i].label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        TextField("", text: $draft[i].value, axis: .vertical)
                            .lineLimit(1...3).textFieldStyle(.plain).font(.caption)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                            .opacity(draft[i].included ? 1 : 0.4)
                            .onChange(of: draft[i].value) { _, v in
                                if v.count > BlueprintField.maxLength { draft[i].value = String(v.prefix(BlueprintField.maxLength)) }
                            }
                    }
                }
            }
            Button {
                save()
            } label: {
                Text("Save & Log Update").font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(Color.accentColor)

            resetControl
        }
    }

    /// Double-confirm destructive reset: tap once arms it, tap again (or Cancel) resolves it.
    private var resetControl: some View {
        HStack(spacing: 10) {
            if confirmingReset {
                Text("Delete everything and start over?").font(.caption2).foregroundStyle(.red)
                Button("Cancel") { confirmingReset = false }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                Button("Yes, delete it") {
                    BlueprintStore.delete(projectFolder: projectFolder)
                    blueprint = nil; draft = []; editing = false; confirmingReset = false
                }
                .buttonStyle(.plain).font(.caption2.weight(.semibold)).foregroundStyle(.red)
            } else {
                Button("Start over…") { confirmingReset = true }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    private func swap() {
        blueprint?.swapWithPrevious()
        if let blueprint { BlueprintStore.save(blueprint, projectFolder: projectFolder) }
    }

    private func save() {
        // The very first fill-in (right after picking a template) just completes v1 — it isn't an
        // "update" of anything yet, so it shouldn't bump the version or log an activity line on top of
        // "Blueprint created".
        let isFirstFillIn = blueprint?.version == 1 && (blueprint?.fields.allSatisfy { $0.value.isEmpty } ?? false)
        if isFirstFillIn {
            blueprint?.fields = draft
        } else {
            blueprint?.logUpdate(fields: draft)
        }
        if let blueprint { BlueprintStore.save(blueprint, projectFolder: projectFolder) }
        editing = false
    }
}
