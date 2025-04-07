//
//  WebKitView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import WebKit

@MainActor
public protocol WebViewDelegate: AnyObject {
    func didFinishNavigation(to url: URL)
}

public struct WebView: View {
    
    public let title: String
    public let url: URL
    public let background: Color
    
    @StateObject var viewModel: WebViewViewModel
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Init -
    
    public init(delegate: WebViewDelegate? = nil, title: String, url: URL, background: Color) {
        self.title = title
        self.url = url
        self.background = background
        self._viewModel = StateObject(wrappedValue: WebViewViewModel(delegate: delegate))
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image.asset(.close)
                        .padding(15)
                        .padding(.leading, 10)
                }
                
                Spacer()
                
                Text(title)
                    .font(.appTitle)
                    .foregroundStyle(Color.textMain)
                
                Spacer()
                
                Button {
                    viewModel.reload()
                } label: {
                    Image.asset(.reload)
                        .padding(15)
                        .padding(.trailing, 10)
                }
            }
            .frame(height: 54, alignment: .center)
            
            WebViewContainer(
                url: url,
                viewModel: viewModel,
                background: background
            )
        }
        .background(background)
        .toolbar(.hidden)
    }
}

@MainActor
class WebViewViewModel: ObservableObject {
    
    private(set) var webView: WKWebView!
    
    private weak var delegate: WebViewDelegate?
    
    init(delegate: WebViewDelegate?) {
        self.delegate = delegate
    }
    
    func makeWebView(scriptHandler: WKScriptMessageHandler, block: (inout WKWebView) -> Void) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(scriptHandler, name: .webChannel)
        
        var webView: WKWebView = FullWebView(frame: .zero, configuration: configuration)
        block(&webView)
        
        self.webView = webView
        return webView
    }
    
    func reload() {
        webView.reload()
    }
    
    func handleWebViewChannelMessage(_ message: WKScriptMessage) {
//        guard let jsonMessage = message.body as? [String: Any] else {
//            return
//        }
//        
//        guard let type = jsonMessage["type"] as? String, type == "PLAID_NEW_ACH_LINK" else {
//            return
//        }
//        
//        guard let payload = jsonMessage["payload"] as? String else {
//            return
//        }
//        
//        print("Plaid ACH: \(payload)")
    }
    
    func didFinishNavigation(to url: URL) {
        delegate?.didFinishNavigation(to: url)
    }
}

struct WebViewContainer: UIViewRepresentable {
    
    private let url: URL
    private let viewModel: WebViewViewModel
    private let background: Color
    
    // MARK: - Init -
    
    init(url: URL, viewModel: WebViewViewModel, background: Color) {
        self.url = url
        self.viewModel = viewModel
        self.background = background
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel)
    }
    
    func makeUIView(context: Context) -> UIView {
        viewModel.makeWebView(scriptHandler: context.coordinator) { webView in
            webView.backgroundColor = UIColor(background)
            webView.underPageBackgroundColor = UIColor(background)
            webView.isOpaque = false
            
            webView.navigationDelegate = context.coordinator
            webView.uiDelegate = context.coordinator
            
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension String {
    static let webChannel: String = "webViewChannel"
}

// MARK: - Coordinator -

extension WebViewContainer {
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        
        let viewModel: WebViewViewModel
        
        init(_ viewModel: WebViewViewModel) {
            self.viewModel = viewModel
        }
        
        // MARK: - WKNavigationDelegate -
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else {
                return
            }
            
            viewModel.didFinishNavigation(to: url)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
        
        // MARK: - WKUIDelegate -
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            WKWebView(
                frame: webView.frame,
                configuration: configuration
            )
        }
        
        // MARK: - WKScriptMessageHandler -
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == .webChannel {
                viewModel.handleWebViewChannelMessage(message)
            }
        }
    }
}

private class FullWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}
