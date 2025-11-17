//
//  ToolbarCloseButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct ToolbarCloseButton: View {
    
    public let action: VoidAction
    
    // MARK: - Init -
    
    public init(binding: Binding<Bool>) {
        self.action = { binding.wrappedValue = false }
    }
    
    public init(action: @escaping VoidAction) {
        self.action = action
    }
    
    // MARK: - Body -
    
    public var body: some View {
        Button {
            action()
        } label: {
            Image.asset(.close)
                .padding([.leading, .trailing], 5)
                .padding([.top, .bottom], 5)
        }
    }
}

// MARK: - Previews -

struct ToolbarCloseButton_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            VStack {
                Text("Some View")
            }
            .toolbar {
                ToolbarCloseButton {}
            }
        }
    }
}
