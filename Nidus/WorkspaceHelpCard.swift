//
//  WorkspaceHelpCard.swift
//  Nidus
//
//  The in-app help popup reachable from the Workspace sidebar's "?" — a calm glass card that
//  explains, in plain words, how the workspace works and how to add tools, so a newcomer never has
//  to leave the app to get oriented. (The top-right Git button is for the repo itself.)
//

import SwiftUI

struct WorkspaceHelpCard: View {
    let onClose: () -> Void

    private static let body = """
    This is your project's workspace — one calm screen holding only the tools this project needs. \
    No tabs, no navigating; everything is in front of you.

    Press ⌘E (or the Customize button) to rearrange, add or remove tools — and to edit the project \
    itself: its name, icon, description, discipline or linked folder.

    Quick keys: F to search, T for a task, I for an idea. Hover the left edge for the project \
    sidebar; ⌘N opens a fresh Greeting for a new project.

    Need a tool that isn't here? Open an issue on Git, ask your LLM of choice, or build it yourself \
    — there's a simple skill in the repo to help. You own everything you make: it all lives as \
    plain Markdown inside your vault.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("How Nidus works")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .nidusGlass(Circle(), interactive: true)
            }
            ScrollView {
                Text(Self.body)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(22)
        .frame(width: 340, height: 420)
        .nidusGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }
}
