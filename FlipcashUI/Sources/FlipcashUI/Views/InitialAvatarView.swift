//
//  InitialAvatarView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct InitialAvatarView: View {
    
    private let size: CGFloat
    private let initials: String
    
    // MARK: - Init -
    
    public init(size: CGFloat, initials: String) {
        self.size = size
        self.initials = initials.prefix(2).uppercased()
    }
    
    // MARK: - Body -
    
    public var body: some View {
        ZStack {
            Circle()
                .fill(Color.textMain.opacity(0.07))
                .background(
                    Circle()
                        .strokeBorder(Color.textMain.opacity(0.1), lineWidth: 1)
                )
            Text(initials)
                .padding(8)
                .minimumScaleFactor(0.5)
                .font(.default(size: 14, weight: .bold))
                .foregroundColor(.textMain.opacity(0.8))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Previews -

struct InitialAvatarView_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                InitialAvatarView(size: 44, initials: "JS")
                InitialAvatarView(size: 44, initials: "WW")
                InitialAvatarView(size: 44, initials: "W")
                InitialAvatarView(size: 44, initials: "stuff")
            }
        }
    }
}
