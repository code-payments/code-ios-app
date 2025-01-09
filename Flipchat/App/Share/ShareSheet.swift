//
//  ShareSheet.swift
//  Code
//
//  Created by Dima Bart on 2022-01-25.
//

import SwiftUI
import CodeUI

@MainActor
struct ShareSheet: UIViewControllerRepresentable {

    let activityItem: UIActivityItemSource
    let completion: VoidAction
    
    // MARK: - Init -
    
    init(activityItem: UIActivityItemSource, completion: @escaping VoidActionSendable) {
        self.activityItem = activityItem
        self.completion = completion
    }
    
    // MARK: - UIViewControllerRepresentable -
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = CustomActivityController(activityItems: [activityItem], applicationActivities: nil)
        controller.dismissHandler = completion
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    
    // MARK: - Static Invocation -
    
    static func present(activityItem: UIActivityItemSource, completion: @escaping VoidAction) {
        let controller = CustomActivityController(activityItems: [activityItem], applicationActivities: nil)
        controller.dismissHandler = {
            Task { @MainActor in
                completion()
            }
        }
        
        UIApplication.shared.rootViewController?.present(controller, animated: true, completion: nil)
    }
    
    @MainActor
    static func present(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        UIApplication.shared.rootViewController?.present(controller, animated: true, completion: nil)
    }
}

// MARK: - CustomActivityController -

@MainActor
private class CustomActivityController: UIActivityViewController {
    
    nonisolated(unsafe) var dismissHandler: VoidAction?
    
    deinit {
        dismissHandler?()
    }
}

// MARK: - UIApplication -

extension UIApplication {
    var rootViewController: UIViewController? {
        keyWindow?.rootViewController?.topMostController
    }
    
    var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first(where: { $0 is UIWindowScene })
            .flatMap({ $0 as? UIWindowScene })?.windows
            .first(where: \.isKeyWindow)
    }
}

private extension UIViewController {
    var topMostController: UIViewController {
        if let controller = presentedViewController {
            return controller.topMostController
        }
        return self
    }
}
