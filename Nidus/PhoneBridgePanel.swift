//
//  PhoneBridgePanel.swift
//  Nidus
//
//  The pairing surface: a QR to scan, a pairing code to carry by hand, and an Advanced section for the
//  relay. Opened from the sidebar (next to "?") — pairing belongs to the vault, not to a project.
//

import SwiftUI

struct PhoneBridgePanel: View {
    let onClose: () -> Void

    @Environment(NidusModel.self) private var model
    @Environment(PhoneBridge.self) private var bridge

    @State private var relayDraft = ""
    @State private var verifying = false
    @State private var verifyResult: Bool?
    @State private var copied = false
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3").font(.title3).foregroundStyle(.secondary)
                Text("Capture from your phone").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                NotebookCircleButton(system: "xmark", action: onClose)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            Divider().opacity(0.4)
            TidyScroll {
                VStack(alignment: .leading, spacing: 18) {
                    if bridge.isConfigured { paired } else { setupNotice }
                    advanced
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 580)
        .glassCard()
        .background(Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0))
        .onAppear {
            relayDraft = bridge.relayBase
            if bridge.isConfigured { Task { await bridge.pushDown(model, force: true) } }
        }
    }

    // MARK: Not set up yet

    private var setupNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One-time setup").font(.subheadline.weight(.semibold))
            Text("Your phone hands captures to Nidus through a small mailbox you own — a free Cloudflare Worker. Deploy it once (see relay/README.md in the Nidus repo), then paste its URL below.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Nothing else is needed: no account, no password. Your vault stays on your machine.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.25)))
    }

    // MARK: Paired

    private var paired: some View {
        VStack(spacing: 14) {
            // A QR needs dark-on-light to scan reliably, whatever the app's theme is doing.
            if let qr = nidusQRImage(bridge.pairingURL) {
                qr.resizable().interpolation(.none)
                    .frame(width: 200, height: 200)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            }
            Text("Scan with your phone's camera, then add it to your Home Screen.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            pairingCodeRow
            syncRow
        }
        .frame(maxWidth: .infinity)
    }

    /// iOS gives a home-screen web app its OWN storage container, so a pairing made in Safari is invisible
    /// to the installed app. The code is the hand-carried fallback — offer it plainly, not buried.
    private var pairingCodeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pairing code").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(bridge.pairingCode)
                    .font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                Button(copied ? "Copied" : "Copy") {
                    nidusCopyToClipboard(bridge.pairingCode)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            Text("If the installed app on your phone starts unpaired, paste this into it.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var syncRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await bridge.pushDown(model, force: true)
                    await bridge.pullUp(model)
                }
            } label: {
                Label(bridge.busy ? "Checking…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .disabled(bridge.busy)
            if let message = bridge.lastMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Advanced

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.3)
            Text("ADVANCED").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.tertiary)
            Text("Your relay").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("https://nidus-relay.<you>.workers.dev", text: $relayDraft)
                    .textFieldStyle(.plain).font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                Button(verifying ? "Checking…" : "Verify & use") { verify() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(verifying || relayDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let ok = verifyResult {
                Text(ok ? "Verified — pairing updated. Re-scan the QR on your phone."
                        : "That URL didn't behave like a Nidus relay (a write-then-read probe failed).")
                    .font(.caption2).foregroundStyle(ok ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Changing the relay unpairs every phone — a different relay is a different mailbox.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)

            if bridge.isConfigured { resetRow }
        }
    }

    private var resetRow: some View {
        HStack(spacing: 8) {
            if confirmingReset {
                Text("Start a new pairing? Every paired phone stops working.")
                    .font(.caption2).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("Cancel") { confirmingReset = false }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                Button("Reset") {
                    bridge.regeneratePairing()
                    confirmingReset = false
                    Task { await bridge.pushDown(model, force: true) }
                }
                .buttonStyle(.plain).font(.caption2.weight(.semibold)).foregroundStyle(.red)
            } else {
                Button("Reset pairing…") { confirmingReset = true }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.red.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func verify() {
        verifying = true
        verifyResult = nil
        let candidate = relayDraft.trimmingCharacters(in: .whitespaces)
        Task {
            let ok = await bridge.verifyRelay(candidate)
            verifying = false
            verifyResult = ok
            if ok {
                bridge.relayBase = candidate
                await bridge.pushDown(model, force: true)   // seed the mailbox so the first scan isn't empty
            }
        }
    }
}
