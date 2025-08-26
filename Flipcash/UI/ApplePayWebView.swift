//
//  ApplePayWebView.swift
//  Code
//
//  Created by Dima Bart on 2025-08-08.
//

import SwiftUI
import WebKit

public struct ApplePayWebView: UIViewRepresentable {
    
    private let url: URL
    private let onMessage: ((ApplePayEvent) -> Void)?

    // MARK: - Init -
    
    public init(url: URL, onMessage: ((ApplePayEvent) -> Void)? = nil) {
        self.url = url
        self.onMessage = onMessage
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: .messageHandlerName)
    }

    public func makeUIView(context: Context) -> WKWebView {
        
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: .messageHandlerName)
        
        let js = """
        window.addEventListener('message', function(event) {
            window.webkit.messageHandlers.\(String.messageHandlerName).postMessage(event.data);
        });
        """
        
        let userScript = WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(userScript)
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        context.coordinator.contentController = contentController
        
        webView.load(URLRequest(url: url))
        
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        // No dynamic updates required
    }
}

// MARK: - Coordinator -

extension ApplePayWebView {
    public class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        
        weak var contentController: WKUserContentController?
        
        private let parent: ApplePayWebView

        init(parent: ApplePayWebView) {
            self.parent = parent
        }
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            print("[WEBVIEW] Received message \(message.name): \(message.body)")
            
            guard let string = message.body as? String else {
                return
            }
            
            let content = Data(string.utf8)
            guard let applePayEvent = try? JSONDecoder().decode(ApplePayEvent.self, from: content) else {
                return
            }
            
            if let webView = message.webView {
                if applePayEvent.event == .loadSuccess {
                    let jsAutoClick = """
                                (function() {
                                    // First, try the <apple-pay-button> element
                                    const customEl = document.querySelector('apple-pay-button');
                                    if (customEl && customEl.shadowRoot) {
                                        const btn = customEl.shadowRoot.querySelector('button');
                                        if (btn) { btn.click(); return; }
                                    }
                                    // Fallback: find a button by its text
                                    const fallbackBtn = Array.from(document.querySelectorAll('button'))
                                        .find(b => b.textContent.trim().includes('Buy with Apple Pay'));
                                    if (fallbackBtn) { fallbackBtn.click(); }
                                })();
                                """
                    webView.evaluateJavaScript(jsAutoClick) { _, error in
                        if let e = error {
                            print("Auto-click error:", e)
                        }
                    }
                }
            }
            
            parent.onMessage?(applePayEvent)
        }
        
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Optional: handle load completion
        }
        
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Navigation error: \(error.localizedDescription)")
        }

        deinit {
            print("[WEBVIEW] Deallocating ApplePayWevView coordinator")
            contentController?.removeScriptMessageHandler(forName: .messageHandlerName)
        }
    }
}

public struct ApplePayEvent: Codable {
    public let name: String
    
    public var event: Event? {
        Event(rawValue: name)
    }
    
    public enum Event: String {
        case loadPending    = "onramp_api.load_pending"
        case loadSuccess    = "onramp_api.load_success"
        case loadError      = "onramp_api.load_error"
        
        case commitSuccess  = "onramp_api.commit_success"
        case commitError    = "onramp_api.commit_error"
        
        case pollingStart   = "onramp_api.polling_start"
        case pollingSuccess = "onramp_api.polling_success"
        case pollingError   = "onramp_api.polling_error"
        
        case cancelled      = "onramp_api.cancel"
    }

    private enum CodingKeys: String, CodingKey {
        case name = "eventName"
    }
}

private extension String {
    static let messageHandlerName = "coinbasepayment"
}
