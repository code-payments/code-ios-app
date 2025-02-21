//
//  Notification+Keyboard.swift
//  Code
//
//  Created by Dima Bart on 2025-02-19.
//

import UIKit

extension Notification {
    
    @MainActor
    func extractKeyboardParameters(in view: UIView) -> KeyboardParameters? {
        guard let userInfo else {
            return nil
        }
        
        let animationCurve: UIView.AnimationOptions
        if let rawCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt {
            animationCurve = .init(rawValue: rawCurve << 16)
        } else {
            animationCurve = .curveEaseInOut
        }
        
        let duration   = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0
        let endFrame   = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! CGRect
        let startFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! CGRect
        
        let convertedStartFrame = view.convert(startFrame, from: nil)
        let convertedEndFrame   = view.convert(endFrame, from: nil)
        
        return KeyboardParameters(
            duration: duration,
            animationCurve: animationCurve,
            startFrame: convertedStartFrame,
            endFrame: convertedEndFrame
        )
    }
}

struct KeyboardParameters {
    var duration: TimeInterval
    var animationCurve: UIView.AnimationOptions
    var startFrame: CGRect
    var endFrame: CGRect
}
