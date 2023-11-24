//
//  Flow.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Flow<Content>: View where Content: View {
 
    @Binding public var isActive: Bool
    public let content: () -> Content
    
    // MARK: - Init -
    
    public init(isActive: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self._isActive = isActive
        self.content = content
    }
    
    // MARK: - Body -
    
    public var body: some View {
        NavigationLink(
            destination: VStack { content() },
            isActive: $isActive,
            label: {
                EmptyView()
            }
        )
    }
}
