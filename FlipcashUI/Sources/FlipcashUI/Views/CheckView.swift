//
//  CheckView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct CheckView: View {
    
    public let active: Bool
    
    public init(active: Bool) {
        self.active = active
    }
    
    public var body: some View {
        ZStack {
            if active {
                Circle()
                    .fill(Color.checkmarkBackground)
                Image.asset(.checkmark)
            } else {
                Circle()
                    .strokeBorder(Color.white)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Previews -

struct CheckView_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                CheckView(active: true)
                CheckView(active: false)
            }
        }
        .accentColor(.textMain)
        .previewLayout(.fixed(width: 180, height: 180))
    }
}
