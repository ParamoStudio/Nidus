//
//  VaultPickerView.swift
//  Nidus
//
//  First run (or when the vault can't be found): a small panel — same glass aesthetic as the
//  Greeting — to create a new NidusVault or locate an existing one. "Locate" only accepts a folder
//  carrying Nidus's validity marker, so you can't point it at a random folder by mistake.
//
//  First-time-ever flourish: a short welcome sequence plays once — a line of text fades in where
//  the metaball lives, the bottom "?" briefly glows in the accent colour, then the metaball
//  recomposes from the sides into the centre (ferrofluid) and stays there, alive. Persisted by a
//  flag so it never repeats.
//

import SwiftUI
import UniformTypeIdentifiers

struct VaultPickerView: View {
    @Environment(NidusModel.self) private var model
    @State private var importing = false
    @State private var mode: Mode = .create

    // First-time welcome sequence.
    @AppStorage("nidus.intro.welcomeSeen") private var welcomeSeen = false
    @State private var showWelcomeText = false
    @State private var metaballVisible = false
    @State private var metaballIntroStart: Date? = nil
    @State private var highlightHelp = false
    @State private var showingInfo = false
    @State private var introStarted = false

    private enum Mode { case create, locate }

    /// Practical, newcomer-first guide — shown ABOVE the condensed repo blurb in the help dialog.
    private static let welcomeText = """
    Nidus helps you manage, orchestrate and keep a calm overview of the projects you're actually \
    working on — your tasks, ideas, direction, and the mistakes worth remembering.

    Start by creating your vault: a folder where all your data lives, in plain files you always own \
    and can open anywhere.

    Once it's set up, create projects and link each one to a real folder on your computer. Open a \
    project and you get its workspace — a single screen holding just the tools that project needs, \
    which you can change anytime. No navigating, no clutter, no distractions; everything you need \
    in one calm place.

    Inside any workspace there's always a help button, so the basics are one tap away whenever you \
    forget or need a nudge.
    """

    private static let infoText = """
    Nidus is a lightweight, open-source way to orchestrate your projects in a calm, focused \
    workflow — each project is a workspace grid holding just the tools it needs.

    Need a tool that isn't here? Open an issue on Git, ask your LLM of choice, or build it \
    yourself. There's a simple skill in the repo to help you customize it.

    You own everything you create. No cloud. No subscriptions. No bullshit. It all lives in a \
    self-contained folder of Markdown files, so any LLM can fold it into your knowledge base.

    Enjoy!
    """

    var body: some View {
        ZStack {
            content
            if showingInfo { infoOverlay }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                switch mode {
                case .create: model.createVault(in: url)
                case .locate: model.openExistingVault(at: url)
                }
            case .failure(let error):
                model.reportImportFailure(error)
            }
        }
        .onAppear { startIntro() }
    }

    // MARK: - Main content

    private var content: some View {
        VStack(spacing: 0) {
            Text("NIDUS")
                .font(.system(size: 13, weight: .semibold)).tracking(3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)

            Spacer(minLength: 20)

            // The hero slot: the welcome line lives here first, then the metaball composes in.
            avatarSlot
                .frame(height: 132)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Text("Set up your vault")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("A NidusVault folder keeps everything as readable Markdown. You choose where it lives.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 11) {
                vaultButton("Create new vault", icon: "plus", accent: true) { mode = .create; importing = true }
                vaultButton("Locate existing", icon: "folder", accent: false) { mode = .locate; importing = true }
            }
            .padding(.top, 26)

            if let error = model.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }

            Spacer(minLength: 22)

            helpButton
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Welcome text → metaball, both centred in the same slot so layout never jumps.
    private var avatarSlot: some View {
        ZStack {
            if showWelcomeText {
                Text("Hi! First time using Nidus?")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity.combined(with: .offset(y: -10))))
            }
            if metaballVisible {
                // The app's "avatar" — the living metaball, free (no circle). Only here, not in the
                // everyday Greeting.
                MetaballView(seed: 42, avatar: true, introStart: metaballIntroStart)
                    .frame(width: 118, height: 118)
            }
        }
    }

    private func vaultButton(_ title: LocalizedStringKey, icon: String, accent: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect((accent ? Glass.regular.tint(.accentColor.opacity(0.45)) : .regular).interactive(),
                     in: Capsule())
    }

    /// Bottom-centred "?" — opens the info popover; glows in the accent during the welcome beat.
    private var helpButton: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { showingInfo = true }
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(highlightHelp ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .overlay {
            Circle().strokeBorder(Color.accentColor.opacity(highlightHelp ? 0.9 : 0), lineWidth: 1.5)
        }
        .shadow(color: .accentColor.opacity(highlightHelp ? 0.55 : 0), radius: highlightHelp ? 10 : 0)
        .animation(.easeInOut(duration: 0.5), value: highlightHelp)
    }

    // MARK: - Info popover

    private var infoOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.22)) { showingInfo = false }
                }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Welcome to Nidus")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { showingInfo = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Practical first — what to do and what Nidus is for.
                        Text(Self.welcomeText)
                            .font(.callout)
                            .foregroundStyle(.primary.opacity(0.92))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().opacity(0.4)
                        // The condensed philosophy / repo blurb, for whoever wants it.
                        Text(Self.infoText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(22)
            .frame(width: 312, height: 432)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    // MARK: - Welcome sequence

    /// Drives the one-time welcome with absolute-time scheduling (robust to view re-renders, unlike
    /// a `.task` + `Task.sleep`, whose sleeps get cancelled and skipped on the first re-layout).
    private func startIntro() {
        guard !introStarted else { return }
        introStarted = true

        guard !welcomeSeen else {
            // Already welcomed before: show the composed, living metaball straight away.
            metaballVisible = true
            metaballIntroStart = nil
            return
        }
        welcomeSeen = true

        // 1. The greeting line fades/slides in where the metaball will live.
        withAnimation(.easeOut(duration: 0.6)) { showWelcomeText = true }
        // 2. A beat later, nudge attention to the "?" with an accent glow…
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.5)) { highlightHelp = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.6)) { highlightHelp = false }
        }
        // 3. The line fades out…
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeIn(duration: 0.5)) { showWelcomeText = false }
        }
        // 4. …and the metaball composes from the sides into the centre, then lives there.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
            metaballIntroStart = Date()
            metaballVisible = true
        }
    }
}
