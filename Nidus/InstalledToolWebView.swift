//
//  InstalledToolWebView.swift
//  Nidus
//
//  Renders an installed tool's `html` node in a sandboxed WKWebView — the "escape hatch" for bespoke
//  widgets (a chord grid, a calculator, a canvas). Inside, a `window.nidus` bridge lets the widget
//  read/write THIS tool's own cards (via a reply-based message handler), and get notified when the
//  cards change. No network unless the node declares `network: true`.
//

import SwiftUI
import WebKit

struct InstalledToolWebView: View {
    let html: String
    let height: Double?
    let network: Bool
    let run: InstalledToolEngine.Run

    @Environment(NidusModel.self) private var model

    var body: some View {
        WebViewContainer(html: html, network: network, primaryFile: run.primaryFile,
                         toolID: run.tool.id, fileTick: model.fileChangeTick)
            .frame(height: height ?? 260)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
    }
}

#if canImport(AppKit)
private typealias PlatformViewRepresentable = NSViewRepresentable
#else
private typealias PlatformViewRepresentable = UIViewRepresentable
#endif

private struct WebViewContainer: PlatformViewRepresentable {
    let html: String
    let network: Bool
    let primaryFile: URL?
    let toolID: String
    let fileTick: Int   // bump → re-notify the widget its cards changed

    func makeCoordinator() -> Coordinator { Coordinator(primaryFile: primaryFile, network: network) }

    private func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        // The nidus bridge shim: cards.all()/add() → reply-based message; on(evt, cb) stores callbacks.
        let shim = """
        window.nidus = {
          cards: {
            all: function(){ return window.webkit.messageHandlers.nidus.postMessage({op:'all'}); },
            add: function(c){ return window.webkit.messageHandlers.nidus.postMessage({op:'add', card:c}); }
          },
          on: function(evt, cb){ window.__nidusHandlers = window.__nidusHandlers || {}; window.__nidusHandlers[evt] = cb; },
          _fire: function(evt){ var h = (window.__nidusHandlers||{})[evt]; if (h) h(); }
        };
        """
        controller.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addScriptMessageHandler(coordinator, contentWorld: .page, name: "nidus")
        config.userContentController = controller
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = coordinator
        coordinator.web = web
        #if canImport(AppKit)
        web.setValue(false, forKey: "drawsBackground")   // transparent, so the panel shows through
        #else
        web.isOpaque = false
        web.backgroundColor = .clear
        #endif
        web.loadHTMLString(html, baseURL: nil)
        return web
    }

    #if canImport(AppKit)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ web: WKWebView, context: Context) { context.coordinator.notifyChanged(tick: fileTick) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.notifyChanged(tick: fileTick) }
    #endif

    final class Coordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        let primaryFile: URL?
        let network: Bool
        weak var web: WKWebView?
        private var lastTick = Int.min

        init(primaryFile: URL?, network: Bool) { self.primaryFile = primaryFile; self.network = network }

        /// Re-notify the widget when the tool's cards changed elsewhere (a native form add, etc.).
        func notifyChanged(tick: Int) {
            guard tick != lastTick else { return }
            lastTick = tick
            web?.evaluateJavaScript("window.nidus && window.nidus._fire('cardsChanged')")
        }

        // The reply-based bridge (async): resolves the JS promise from `postMessage`.
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
                replyHandler(nil, "bad message"); return
            }
            switch op {
            case "all":
                let cards = primaryFile.map { CardStore.read(from: $0) } ?? []
                replyHandler(cards.map(InstalledToolEngine.cardToDict), nil)
            case "add":
                guard let file = primaryFile, let c = body["card"] as? [String: Any] else {
                    replyHandler(nil, "no store"); return
                }
                var card = Card.make(title: (c["title"] as? String) ?? "Untitled",
                                     body: (c["body"] as? String) ?? "")
                if let extra = c["extra"] as? [String: Any] { card.extra = extra.mapValues { "\($0)" } }
                CardStore.append(card, to: file)
                replyHandler(InstalledToolEngine.cardToDict(card), nil)
                web?.evaluateJavaScript("window.nidus && window.nidus._fire('cardsChanged')")
            default:
                replyHandler(nil, "unknown op")
            }
        }

        // Network policy: unless the node declared `network:true`, only allow the initial in-memory
        // load; block navigations to the network.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
            if (scheme == "http" || scheme == "https") && !network {
                decisionHandler(.cancel)   // no network unless the node declared network:true
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
