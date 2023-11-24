//
//  UIApplication+Root.swift
//  Code
//
//  Created by Dima Bart on 2021-03-23.
//

import UIKit

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
