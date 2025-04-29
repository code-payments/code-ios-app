//
//  ShareSheet.swift
//  Code
//
//  Created by Dima Bart on 2022-01-25.
//

import SwiftUI
import FlipcashUI

@MainActor
struct ShareSheet: UIViewControllerRepresentable {

    let activityItem: UIActivityItemSource
    let completion: (Bool) -> Void
    
    // MARK: - Init -
    
    init(activityItem: UIActivityItemSource, completion: @escaping (Bool) -> Void) {
        self.activityItem = activityItem
        self.completion = completion
    }
    
    // MARK: - UIViewControllerRepresentable -
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [activityItem], applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, isCompleted, returnedItems, error in
            completion(isCompleted)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    
    // MARK: - Static Invocation -
    
    static func present(activityItem: UIActivityItemSource, completion: @escaping (Bool) -> Void) {
        let controller = UIActivityViewController(activityItems: [activityItem], applicationActivities: nil)

        controller.completionWithItemsHandler = { activityType, isCompleted, returnedItems, error in
            var result = "Share sheet finished(\(isCompleted ? 1 : 0))"
            
            if let activityType = activityType {
                result = "\(result)\n - Type: \(activityType)"
            }
            
            if let returnedItems = returnedItems {
                result = "\(result)\n - Returned: \(returnedItems)"
            }
            
            if let error = error {
                result = "\(result)\n - Error: \(error)"
            }
            
            print(result)
            completion(isCompleted)
        }
        
        UIApplication.shared.rootViewController?.present(controller, animated: true, completion: nil)
    }
    
    static func present(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        UIApplication.shared.rootViewController?.present(controller, animated: true, completion: nil)
    }
}

// MARK: - UIApplication -

private extension UIApplication {
    var rootViewController: UIViewController? {
        currentKeyWindow?.rootViewController
    }
    
    var currentKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
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
