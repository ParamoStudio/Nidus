//
//  ToolComponents.swift
//  Nidus
//
//  Shared building blocks for tool views (kept separate so each tool file stays self-contained).
//

import SwiftUI

/// A compact add/capture field used at the top of list-style tools.
/// Reports its focus to the model so plain-letter shortcuts don't fire while typing.
struct ToolAddField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let onSubmit: () -> Void

    @Environment(NidusModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($focused)
                .onSubmit(onSubmit)
                #if os(iOS)
                .autocorrectionDisabled()
                #endif
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: focused) { _, isFocused in model.isEditingText = isFocused }
        .onDisappear { if focused { model.isEditingText = false } }
    }
}

/// A scrollable list of `## heading` sections with their lines.
struct ToolSectionList: View {
    let sections: [MarkdownSection]
    var emptyHint: LocalizedStringKey = ""

    var body: some View {
        if sections.isEmpty {
            ToolEmptyHint(emptyHint)
        } else {
            TidyScroll {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 10)
                        if index < sections.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ToolEmptyHint: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Text(text).font(.caption).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
