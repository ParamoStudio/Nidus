//
//  RootWindowView.swift
//  Nidus
//
//  One window = one project. A window starts at the Greeting Panel (no project) and, when a
//  project is opened, the same surface transforms into the Workspace (GUI greeting §12).
//  The vault/config is shared app-wide; the project selection is per-window state.
//

import SwiftUI

struct RootWindowView: View {
    @Environment(NidusModel.self) private var model
    @Environment(ThemeController.self) private var theme
    @Environment(PhoneBridge.self) private var bridge
    @Environment(\.scenePhase) private var scenePhase
    @State private var openProject: ProjectRef?

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()  // blurred desktop behind the window
            AmbientBackground(reduced: isPanel)  // translucent tint (glassier in the Greeting)
            content
        }
        .background(WindowConfigurator(isPanel: isPanel, panelSize: panelSize))
        .preferredColorScheme(theme.isDark ? .dark : .light)
        // A deliberately unhurried cross-fade (~1.5s): switching projects should FEEL like stepping into
        // another workspace — a calm, intentional beat, not an instant swap. `easeInOut` is kept gentle
        // (no snappy mid-acceleration) so it reads as a soft dissolve. Part of the app's whole cadence.
        .animation(.easeInOut(duration: 1.5), value: openProject)
        // Lightweight external-change detection: re-read files when the app reactivates. Also the moment
        // to collect anything captured on the phone — non-blocking, and safe with several devices because
        // the desktop deletes each record from the relay only after filing it.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.notifyFileChange()
            guard bridge.isConfigured else { return }
            Task {
                await bridge.pullUp(model)
                await bridge.pushDown(model)   // dirty-flagged: only writes if the project list changed
            }
        }
    }

    /// The window is a small floating panel for both entry surfaces (vault picker + greeting);
    /// it becomes the large workspace window only once a project is open.
    private var isPanel: Bool { openProject == nil }

    /// Both panel surfaces (vault picker + greeting) use the exact same size.
    private var panelSize: CGSize { CGSize(width: 360, height: 600) }

    @ViewBuilder
    private var content: some View {
        if !model.hasVault {
            VaultPickerView()
        } else if let ref = openProject {
            WorkspaceView(ref: ref, onBack: {
                withAnimation { openProject = nil }
            }, onOpen: { newRef in
                model.markOpened(newRef)
                withAnimation { openProject = newRef }
            })
            // Key by project so switching from one to another cross-fades (a beat of "entering another
            // workspace") instead of swapping content in place instantly.
            .id(ref)
            .transition(.opacity)
        } else {
            GreetingPanelView { ref in
                withAnimation { openProject = ref }
            }
        }
    }
}
