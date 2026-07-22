//
//  NotebookDocumentView.swift
//  Nidus
//
//  The document viewer for imported files (pdf/txt/docx/odt/pages/rtf). We don't reimplement a reader
//  — QuickLook renders every one of these for free. A back arrow returns to the library; "Open in
//  default app" hands the file to its own application; Delete removes it. No editing here by design.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
import QuickLookUI
#elseif canImport(UIKit)
import UIKit
import QuickLook
#endif

struct NotebookDocumentView: View {
    let item: NotebookStore.Item
    let toolName: String
    let projectFolder: URL?
    let onBack: () -> Void

    @Environment(NidusModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.4)
            QuickLookPreview(url: item.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.03))
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            NotebookCircleButton(system: "chevron.left", action: onBack)
            Image(systemName: NotebookIcon.symbol(for: item))
                .foregroundStyle(NotebookIcon.tint(for: item))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.headline).lineLimit(1)
                Text(NotebookIcon.subtitle(for: item)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            #if os(macOS)
            Button { NSWorkspace.shared.open(item.url) } label: {
                Label("Open in default app", systemImage: "arrow.up.forward.app").font(.callout)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            #endif
            Button(role: .destructive) { delete() } label: {
                Image(systemName: "trash").font(.callout)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            NotebookCircleButton(system: "xmark", action: onBack)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func delete() {
        NotebookStore.delete(item, projectFolder: projectFolder)
        model.notifyFileChange()
        onBack()
    }
}

// MARK: - QuickLook bridge

#if os(macOS)
struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = true   // let AppKit tear it down with the window (no manual close)
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url { view.previewItem = url as NSURL }
    }
}
#else
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif
