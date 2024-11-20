//
//  MessageTitle.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI

public struct MessageTitle: View {
    
    public let text: String
        
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        HStack(alignment: .top) {
            Spacer()
            Text(text)
                .font(.appTextSmall)
                .foregroundColor(.textSecondary)
//                .background(Color.backgroundMessageReceived.opacity(0.5))
//                .cornerRadius(99)
            Spacer()
        }
    }
}
