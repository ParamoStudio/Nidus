//
//  AddProjectView.swift
//  Nidus
//
//  The "new project" surface — a small ritual of intention, not a form. The Greeting morphs into
//  this (blur) and back. Centred: a (near-transparent) icon, the prompt "What are you building?",
//  the project name (the moment), a discreet discipline typeahead (choose or create), a single
//  line for the project's intention, and Create Workspace. Glass matches the Greeting exactly.
//  Phase-1 icons are SF Symbols; the metaball bank + custom image import come next.
//

import SwiftUI
import UniformTypeIdentifiers

struct AddProjectView: View {
    @Environment(NidusModel.self) private var model
    /// Morph back to the Greeting.
    let onCancel: () -> Void
    /// Created (or saved) — open it (and close the surface). In edit mode the ref may have changed
    /// (e.g. moved to another discipline), so the caller re-opens whatever we pass back.
    let onCreate: (ProjectRef) -> Void
    /// When set, the panel edits this existing project instead of creating a new one.
    var editing: ProjectRef? = nil

    @State private var defaultSeed = Int.random(in: 0..<1_000_000)
    @State private var iconChoice: IconChoice = .metaball(0)
    @State private var showingPicker = false
    @State private var importing = false
    @State private var importMode: ImportMode = .icon
    @State private var linkedURL: URL?
    @State private var disciplineText = ""
    @State private var title = ""
    @State private var intention = ""
    @FocusState private var focus: Field?

    private enum Field { case name, discipline, intention }
    private enum ImportMode { case icon, folder }
    enum IconChoice: Equatable { case metaball(Int); case bauhaus(Int); case builtin(String); case image(URL) }

    private var disciplines: [Discipline] { model.config?.disciplines ?? [] }

    private var disciplineSuggestions: [Discipline] {
        let q = disciplineText.trimmingCharacters(in: .whitespaces)
        // Empty field, or the text already names an existing discipline → no active filter, so show
        // an overview: the three disciplines with the most projects (so you don't type a near-dupe
        // like "cerámica" vs "cerámicas" from memory).
        let exact = disciplines.contains { $0.name.caseInsensitiveCompare(q) == .orderedSame }
        if q.isEmpty || exact {
            return Array(disciplines.sorted { $0.projects.count > $1.projects.count }.prefix(3))
        }
        // Filtering: disciplines whose name contains the partial text.
        return Array(disciplines.filter {
            $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }.prefix(3))
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !disciplineText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            topRow
            Spacer(minLength: 8)
            VStack(spacing: 16) {
                iconSphere
                VStack(spacing: 3) {
                    Text(editing == nil ? "New project" : "Edit project")
                        .font(.caption2.weight(.semibold)).textCase(.uppercase).tracking(1.6)
                        .foregroundStyle(.secondary)
                    Text(editing == nil ? "What are you building?" : "Refine your project")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                nameCell
                disciplineCell
                intentionField
            }
            Spacer(minLength: 8)
            createButton
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            prefillIfEditing()
            if iconChoice == .metaball(0) { iconChoice = .metaball(defaultSeed) }
            DispatchQueue.main.async { focus = .name }
        }
    }

    /// In edit mode, load the existing project's values into the fields.
    private func prefillIfEditing() {
        guard let editing, let hit = model.hit(for: editing) else { return }
        title = hit.project.name
        disciplineText = hit.discipline.name
        intention = hit.project.description ?? ""
        if let linked = hit.project.linkedLocation, linked.deviceId == model.device.id {
            linkedURL = URL(fileURLWithPath: linked.path)
        }
        iconChoice = decodeIcon(hit.project.icon, folderURL: model.projectFolderURL(editing))
    }

    private func decodeIcon(_ icon: String?, folderURL: URL?) -> IconChoice {
        guard let icon else { return .metaball(defaultSeed) }
        if let seed = ProjectGlyph.metaballSeed(icon) { return .metaball(seed) }
        if let n = ProjectGlyph.bauhausIndex(icon) { return .bauhaus(n) }
        if let name = BuiltInIcons.name(icon) { return .builtin(name) }
        if icon == "image", let folderURL {
            return .image(folderURL.appendingPathComponent(ProjectGlyph.imageFileName))
        }
        return .metaball(defaultSeed)
    }

    private var topRow: some View {
        HStack {
            Text("NIDUS")
                .font(.system(size: 13, weight: .semibold)).tracking(3)
                .foregroundStyle(.secondary)
            Spacer()
            IconButton(systemName: "xmark", help: "Cancel") { onCancel() }
        }
    }

    // MARK: - Icon (near-transparent circle, high-contrast glyph)

    private var iconSphere: some View {
        ZStack {
            GlowingRing()
            Circle()
                .trim(from: 0, to: 0.5)
                .fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                .blur(radius: 4)
                .padding(10)
            iconPreviewInner.frame(width: 56, height: 56)
        }
        .frame(width: 84, height: 84)
        .overlay(alignment: .bottomTrailing) {
            Button { showingPicker = true } label: {
                Image(systemName: "photo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Choose an icon or image")
            .offset(x: 4, y: 4)
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) { iconPicker }
        }
        // One importer, two modes — two .fileImporter on one view conflict (only one fires).
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: importMode == .folder ? [.folder] : [.image],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            switch importMode {
            case .icon:
                iconChoice = .image(url)
                showingPicker = false
            case .folder:
                linkedURL = url
            }
        }
    }

    @ViewBuilder
    private var iconPreviewInner: some View {
        switch iconChoice {
        case .metaball(let seed): MetaballView(seed: seed)
        case .bauhaus(let n): BauhausIcon(index: n)
        case .builtin(let name):
            Image(name).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
        case .image(let url):
            if let image = nidusLoadImage(at: url) {
                image.renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            } else {
                MetaballView(seed: defaultSeed)
            }
        }
    }

    /// Popover: import your own image first, then the Bauhaus glyph bank. (The living metaball is
    /// the default — pick the first chip to keep it.)
    private var iconPicker: some View {
        let columns = Array(repeating: GridItem(.fixed(42), spacing: 10), count: 5)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Button { importMode = .icon; importing = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle").font(.system(size: 16))
                            Text("Import image…").font(.callout)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    // So newcomers don't need the repo: imports are tinted to a single colour, so a
                    // background-free logo reads cleanly (anything with a background fills solid).
                    Text("Background-free SVG or PNG — it's tinted to one colour.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center) // popover doesn't inherit the body's centering
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 2)
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    // The living metaball (the default) — first of all.
                    pickerChip(isSelected: isMetaball) {
                        iconChoice = .metaball(defaultSeed); showingPicker = false
                    } content: { MetaballView(seed: defaultSeed) }
                    // Bundled icon set.
                    ForEach(BuiltInIcons.names, id: \.self) { name in
                        pickerChip(isSelected: iconChoice == .builtin(name)) {
                            iconChoice = .builtin(name); showingPicker = false
                        } content: {
                            Image(name).renderingMode(.template).resizable()
                                .aspectRatio(contentMode: .fit).foregroundStyle(.primary)
                        }
                    }
                    ForEach(0..<BauhausIcon.count, id: \.self) { n in
                        pickerChip(isSelected: iconChoice == .bauhaus(n)) {
                            iconChoice = .bauhaus(n); showingPicker = false
                        } content: { BauhausIcon(index: n) }
                    }
                    // The user's own icons from the vault's _icons/ folder (rendered monochrome).
                    ForEach(model.userIcons, id: \.self) { url in
                        pickerChip(isSelected: iconChoice == .image(url)) {
                            iconChoice = .image(url); showingPicker = false
                        } content: {
                            if let image = nidusLoadImage(at: url) {
                                image.renderingMode(.template).resizable()
                                    .aspectRatio(contentMode: .fit).foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .scrollIndicators(.hidden)
        .frame(width: 300, height: pickerHeight)
    }

    /// Tall enough to show every chip WITHOUT scrolling (so no scroll bar ever appears), capped at
    /// a sane max in case the user drops a huge pile of icons into _icons/.
    private var pickerHeight: CGFloat {
        let totalChips = BuiltInIcons.names.count + 1 + BauhausIcon.count + model.userIcons.count
        let rows = Int(ceil(Double(totalChips) / 5.0))
        let visible = min(rows, 8)
        let grid = CGFloat(visible) * 42 + CGFloat(max(visible - 1, 0)) * 10
        return 80 + 12 + grid + 28 // import row + disclaimer + spacing + grid + padding
    }

    private func pickerChip<C: View>(isSelected: Bool, action: @escaping () -> Void,
                                     @ViewBuilder content: () -> C) -> some View {
        Button(action: action) {
            content()
                .frame(width: 30, height: 30)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.16 : 0.04)))
        }
        .buttonStyle(.plain)
    }

    private var isMetaball: Bool { if case .metaball = iconChoice { return true } else { return false } }

    // MARK: - Fields

    /// The moment: the project name, prominent.
    private var nameCell: some View {
        cell(height: 56) {
            TextField("Project name", text: $title)
                .textFieldStyle(.plain)
                .font(.custom("HelveticaNeue-Medium", size: 20)) // Nidus type identity (matches sidebar)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                // Cap the name so it never crowds the identity card's controls (25 is plenty).
                .onChange(of: title) { _, v in if v.count > 25 { title = String(v.prefix(25)) } }
                .onSubmit { if canCreate { create() } else { focus = .discipline } }
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
        }
    }

    /// Discreet discipline typeahead — choose an existing one (suggested) or create a new one.
    private var disciplineCell: some View {
        VStack(spacing: 8) {
            cell(height: 40, subtle: true) {
                TextField("Discipline — choose or create", text: $disciplineText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .focused($focus, equals: .discipline)
                    .submitLabel(.go)
                    .onSubmit { if canCreate { create() } else { focus = .name } }
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
            }
            if !disciplineSuggestions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(disciplineSuggestions) { d in
                        Button { disciplineText = d.name; focus = .intention } label: {
                            Text(d.name)
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(.white.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: disciplineSuggestions.map(\.id))
    }

    /// The intention — one subtle line (label + ghost), so it reads as a field without a heavy cell.
    private var intentionField: some View {
        VStack(spacing: 8) {
            Text("What lives here?")
                .font(.system(size: 15, weight: .semibold)) // stays larger than the 13pt ghost line
                .foregroundStyle(.primary.opacity(0.75))
            // No box — just a baseline line. The ghost wraps (up to 2 lines), disappears on type,
            // and the field grows to 3 lines, then scrolls. Wraps within width: never spills right.
            TextField("one single line to keep focused on the project when you most need it",
                      text: $intention, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.custom("HelveticaNeue", size: 13)) // Nidus type identity (matches sidebar)
                .foregroundStyle(.primary.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2...3)
                .focused($focus, equals: .intention)
                .onKeyPress(.return) { if canCreate { create(); return .handled }; return .ignored }
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
                }
        }
        .padding(.top, 2)
    }

    // MARK: - Create

    private var createButton: some View {
        VStack(spacing: 10) {
            routeButton
            GlassPillButton(title: editing == nil ? "Create Workspace" : "Save changes",
                            tint: .accentColor, action: create)
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.45)
                .animation(.easeOut(duration: 0.2), value: canCreate)
        }
    }

    /// Optional link to the real project folder on disk, so the Workspace can open it later.
    /// Shows the chosen folder's name once set; tap again to change it.
    private var routeButton: some View {
        Button {
            importMode = .folder
            importing = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: linkedURL == nil ? "folder.badge.plus" : "folder.fill")
                    .font(.system(size: 13))
                Text(linkedURL?.lastPathComponent ?? "Project route")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(linkedURL == nil ? .secondary : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    // MARK: - Helpers

    /// A fully-rounded glass cell matching the Greeting's search field. `subtle` dials it back.
    private func cell<Content: View>(height: CGFloat, subtle: Bool = false,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 18)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(subtle ? 0.25 : 0.5), lineWidth: 1))
    }

    private func create() {
        guard canCreate else { return }
        let discName = disciplineText.trimmingCharacters(in: .whitespacesAndNewlines)
        let disciplineID: String
        if let existing = disciplines.first(where: { $0.name.caseInsensitiveCompare(discName) == .orderedSame }) {
            disciplineID = existing.id
        } else if let created = model.createDiscipline(name: discName) {
            disciplineID = created.id
        } else { return }

        let iconString: String
        var importedImageURL: URL?
        switch iconChoice {
        case .metaball(let seed): iconString = "metaball:\(seed)"
        case .bauhaus(let n): iconString = "bauhaus:\(n)"
        case .builtin(let name): iconString = "builtin:\(name)"
        case .image(let url): iconString = "image"; importedImageURL = url
        }

        let linked = linkedURL.map { model.linkedLocation(for: $0) }

        let ref: ProjectRef
        if let editing {
            guard let newRef = model.updateProject(editing, name: title, disciplineID: disciplineID,
                                                    description: intention, icon: iconString,
                                                    linkedLocation: linked) else { return }
            ref = newRef
        } else {
            guard let project = model.createProject(in: disciplineID, name: title,
                                                    description: intention, icon: iconString,
                                                    linkedLocation: linked) else { return }
            ref = ProjectRef(disciplineID: disciplineID, projectID: project.id)
        }
        if let importedImageURL { model.setProjectIconImage(ref, fromImageAt: importedImageURL) }
        model.markOpened(ref)
        onCreate(ref)
    }
}

/// A reactive glass pill button in the app's aesthetic (hover lift, optional accent tint).
private struct GlassPillButton: View {
    let title: LocalizedStringKey
    let tint: Color?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 30)
                .frame(height: 46)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect((tint.map { Glass.regular.tint($0.opacity(0.45)) } ?? .regular).interactive(), in: Capsule())
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}
