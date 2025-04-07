//
//  SeedView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct SeedView: View {
    
    @Binding public var isObfuscated: Bool

    public let words: [String]
    
    private let columns: Int
    private let rows: Int
    
    // MARK: - Init -
    
    public init(words: [String], isObfuscated: Binding<Bool>) {
        self.words = words
        self.columns = 2
        self.rows = words.count / columns
        self._isObfuscated = isObfuscated
    }
    
    // MARK: - Body -
    
    public var body: some View {
        HStack {
            ForEach(0..<columns, id: \.self) { column in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 10) {
                            Text("\((column * rows) + row + 1).")
                                .foregroundColor(.textSecondary)
                                .font(.appTextSmall)
                                .frame(width: 22, alignment: .trailing)
                            
                            if let word = Optional(words[(column * rows) + row]) {
                                ZStack(alignment: .topLeading) {
                                    Text(word)
                                        .foregroundColor(.textMain)
                                        .font(.appTextMedium)
                                        .opacity(isObfuscated ? 0 : 1)
                                    Text(obfuscate(word))
                                        .foregroundColor(.textMain)
                                        .font(.appTextMedium)
                                        .opacity(isObfuscated ? 1 : 0)
                                }
                            }
                        }
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(25)
    }
    
    private func obfuscate(_ word: String) -> String {
        [String](repeating: "-", count: word.count).joined()
    }
}

// MARK: - Previews -

struct SeedView_Previews: PreviewProvider {
    
    private static let phrase12 = "water cook crack oval quarter hood assault horror amateur little cross blind".components(separatedBy: " ")
    
    private static let phrase24 = "water cook crack oval quarter hood assault horror amateur little cross blind ginger business visit opera maze much mansion force mask orange tiny sunny".components(separatedBy: " ")
    
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                SeedView(words: phrase12, isObfuscated: .constant(false))
                SeedView(words: phrase12, isObfuscated: .constant(true))
            }
            .padding(20)
        }
    }
}
