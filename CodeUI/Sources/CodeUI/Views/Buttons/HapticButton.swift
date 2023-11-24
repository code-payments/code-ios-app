//
//  HapticButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct HapticButton<Content>: View where Content: View {
    
    private var action: VoidAction
    private var label: () -> Content
    
    public init(action: @escaping VoidAction, @ViewBuilder label: @escaping () -> Content) {
        self.label  = label
        self.action = {
            Feedback.buttonTap()
            action()
        }
    }
    
    public var body: some View {
        Button(action: action, label: label)
    }
}
