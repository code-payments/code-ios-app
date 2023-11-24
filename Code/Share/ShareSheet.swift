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
    
    init(activityItem: UIActivityItemSource, completion: @escaping VoidAction) {
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
        controller.dismissHandler = completion
        
        ErrorReporting.breadcrumb(.remoteSendShareSheet)
        
        UIApplication.shared.rootViewController?.present(controller, animated: true, completion: nil)
    }
    
    static func present(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        ErrorReporting.breadcrumb(.getFriendOnCodeShareSheet)
        
        UIApplication.shared.rootViewController?.present(controller, animated: true, completion: nil)
    }
}

// MARK: - CustomActivityController -

private class CustomActivityController: UIActivityViewController {
    
    var dismissHandler: VoidAction?
    
    deinit {
        dismissHandler?()
    }
}
