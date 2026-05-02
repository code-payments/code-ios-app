//
//  File.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

public struct AccessKey: View {
    
    public let mnemonic: MnemonicPhrase
    public let url: URL
    
    public init(mnemonic: MnemonicPhrase, url: URL) {
        self.mnemonic = mnemonic
        self.url = url
    }
    
    private var mnemonicGroups: [String] {
        let words = mnemonic.words
        let count = words.count
        let half = count / 2
        
        return [
            words[0..<half].joined(separator: " "),
            words[half..<count].joined(separator: " "),
        ]
    }
    
    public var body: some View {
        Rectangle()
            .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
            .aspectRatio(0.607, contentMode: .fit)
            .overlay(
                Rectangle()
                    .foregroundStyle(.clear)
                    .frame(width: 400, height: 520)
                    .background(
                        EllipticalGradient(
                            stops: [
                                Gradient.Stop(color: .white, location: 0.00),
                                Gradient.Stop(color: .white.opacity(0), location: 1.00),
                            ],
                            center: UnitPoint(x: 0, y: -0.09)
                        )
                    )
                    .background(
                        LinearGradient(
                            stops: [
                                Gradient.Stop(color: Color(red: 0.1, green: 0.1, blue: 0.1), location: 0.17),
                                Gradient.Stop(color: Color(red: 0.23, green: 0.23, blue: 0.23), location: 0.52),
                                Gradient.Stop(color: Color(red: 0.56, green: 0.56, blue: 0.56), location: 0.70),
                                Gradient.Stop(color: Color(red: 0.2, green: 0.2, blue: 0.2), location: 0.84),
                            ],
                            startPoint: UnitPoint(x: -0.12, y: 1.05),
                            endPoint: UnitPoint(x: 1.04, y: 0.08)
                        )
                    )
                    .cornerRadius(8)
                    .blur(radius: 31)
            )
            .overlay(
                VStack {
                    Image.asset(.flipcashLogo)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 50)
                        .foregroundStyle(Color.white)
                    
                    Spacer()
                    
                    QRCode(
                        string: url.absoluteString,
                        showLabel: false,
                        codeColor: .white,
                        backgroundColor: .clear
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 145)
                    
                    Spacer()
                    
                    VStack {
                        ForEach(mnemonicGroups, id: \.self) { group in
                            Text(group)
                        }
                    }
                    .font(.appTextAccessKey)
                }
                    .padding([.top, .bottom], 60)
            )
            .clipped()
            .cornerRadius(10)
            .drawingGroup()
            .frame(maxWidth: 255)
    }
}

#Preview {
    Color.black
        .overlay {
            AccessKey(mnemonic:
                        MnemonicPhrase(words: ["pill", "tomorrow", "foster", "begin", "walnut", "borrow", "virtual", "kick", "shift", "mutual", "shoe", "scatter"])!,
                      url: URL(string: "https://flipcash.com")!
            )
        }
}
