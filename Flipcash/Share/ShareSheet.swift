//
//  ShareSheet.swift
//  Code
//
//  Created by Dima Bart on 2022-01-25.
//

import SwiftUI
import FlipcashUI

enum ShareSheet {

    // MARK: - Static Invocation -
    
    static func present(activityItem: UIActivityItemSource, completion: @escaping (Bool) -> Void) {
        let controller = UIActivityViewController(activityItems: [activityItem], applicationActivities: nil)

        controller.completionWithItemsHandler = { _, isCompleted, _, _ in
            completion(isCompleted)
        }

        UIApplication.shared.rootViewController?.present(controller, animated: true, completion: nil)
    }
}

// MARK: - UIApplication -

private extension UIApplication {
    var rootViewController: UIViewController? {
        currentKeyWindow?.rootViewController?.topMostController
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
