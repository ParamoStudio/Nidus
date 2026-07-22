//
//  NewProjectSheet.swift
//  Nidus
//
//  Create a project from the Greeting Panel: discipline (existing or new) + name +
//  optional linked_location (folder picker, §2.3). On success it opens the new project.
//

import SwiftUI
import UniformTypeIdentifiers

struct NewProjectSheet: View {
    @Environment(NidusModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Called with the new project once created, so the window can open it.
    let onCreate: (ProjectRef) -> Void

    private static let newDisciplineTag = "__new__"

    @State private var disciplineSelection = ""
    @State private var newDisciplineName = ""
    @State private var name = ""
    @State private var linkedURL: URL?
    @State private var isPickingFolder = false

    private var disciplines: [Discipline] { model.config?.disciplines ?? [] }
    private var creatingNewDiscipline: Bool {
        disciplineSelection == Self.newDisciplineTag || disciplines.isEmpty
    }
    private var canCreate: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDiscipline = creatingNewDiscipline
            ? !newDisciplineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !disciplineSelection.isEmpty
        return hasName && hasDiscipline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New project")
                .font(.title2.weight(.semibold))

            disciplineField
            field(label: "Name") {
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
            }
            workingFolderField

            Spacer()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 360)
        .onAppear {
            if disciplineSelection.isEmpty {
                disciplineSelection = disciplines.first?.id ?? Self.newDisciplineTag
            }
        }
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result { linkedURL = urls.first }
        }
    }

    @ViewBuilder
    private var disciplineField: some View {
        field(label: "Discipline") {
            if disciplines.isEmpty {
                TextField("New discipline name", text: $newDisciplineName)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("Discipline", selection: $disciplineSelection) {
                    ForEach(disciplines) { Text($0.name).tag($0.id) }
                    Text("New discipline…").tag(Self.newDisciplineTag)
                }
                .labelsHidden()
                if creatingNewDiscipline {
                    TextField("New discipline name", text: $newDisciplineName)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var workingFolderField: some View {
        field(label: "Working folder (optional)") {
            HStack {
                Text(linkedURL?.path ?? String(localized: "Not linked — a pure thinking/tasks project"))
                    .font(.callout)
                    .foregroundStyle(linkedURL == nil ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if linkedURL != nil {
                    Button("Remove") { linkedURL = nil }
                        .buttonStyle(.borderless)
                }
                Button("Choose…") { isPickingFolder = true }
                    .buttonStyle(.bordered)
            }
            Text("Points at this device (\(model.device.name)). From another device it appears as info.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func field<Content: View>(label: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func create() {
        let disciplineID: String
        if creatingNewDiscipline {
            guard let created = model.createDiscipline(name: newDisciplineName) else { return }
            disciplineID = created.id
        } else {
            disciplineID = disciplineSelection
        }
        let linked = linkedURL.map { model.linkedLocation(for: $0) }
        guard let project = model.createProject(in: disciplineID, name: name, linkedLocation: linked) else { return }
        let ref = ProjectRef(disciplineID: disciplineID, projectID: project.id)
        model.markOpened(ref)
        dismiss()
        onCreate(ref)
    }
}
