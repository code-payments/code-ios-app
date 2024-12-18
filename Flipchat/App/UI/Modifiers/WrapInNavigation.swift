//
//  WrapInNavigation.swift
//  Code
//
//  Created by Dima Bart on 2024-12-17.
//

import SwiftUI
import CodeUI

struct WrapInNavigation: ViewModifier {
    
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(action: dismiss)
                    }
                }
        }
    }
}

extension View {
    func wrapInNavigation(dismiss: @escaping () -> Void) -> some View {
        self.modifier(WrapInNavigation(dismiss: dismiss))
    }
}
