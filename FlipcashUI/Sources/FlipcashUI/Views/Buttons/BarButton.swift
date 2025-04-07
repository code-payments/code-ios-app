//
//  BarButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct BarButton: View {
    
    private let image: Image
    private let action: VoidAction
    
    public init(_ asset: Asset, binding: Binding<Bool>) {
        self.init(asset) {
            binding.wrappedValue.toggle()
        }
    }
    
    public init(_ asset: Asset, action: @escaping VoidAction) {
        self.image = Image.asset(asset)
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            image
                .padding(20)
        }
    }
}

// MARK: - Previews -

struct BarButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            BarButton(.close, action: {})
            BarButton(.history, action: {})
        }
    }
}
