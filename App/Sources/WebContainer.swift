import SwiftUI
import WebKit

/// Mostra a página embutida (www/index.html) — a mesma interface do sistema, adaptada ao iPhone.
struct WebContainer: UIViewRepresentable {
    let ponte: Ponte

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(ponte, name: "nativo")
        cfg.allowsInlineMediaPlayback = true

        let wv = WKWebView(frame: .zero, configuration: cfg)
        let fundo = UIColor(red: 0.114, green: 0.094, blue: 0.086, alpha: 1)
        wv.isOpaque = false
        wv.backgroundColor = fundo
        wv.scrollView.backgroundColor = fundo
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.allowsLinkPreview = false
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        ponte.webView = wv

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") {
            wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
