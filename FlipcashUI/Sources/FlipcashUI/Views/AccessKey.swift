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
            .fill(Color.black)
            .aspectRatio(0.607, contentMode: .fit)
            .overlay(
                Rectangle()
                    .foregroundColor(.clear)
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
                                Gradient.Stop(color: Color(red: 0.22, green: 0.22, blue: 0.26), location: 0.17),
                                Gradient.Stop(color: Color(red: 0.21, green: 0.21, blue: 0.22), location: 0.60),
                                Gradient.Stop(color: Color(red: 0.76, green: 0.76, blue: 0.76), location: 0.81),
                                Gradient.Stop(color: Color(red: 0.1, green: 0.1, blue: 0.1), location: 1.00),
                            ],
                            startPoint: UnitPoint(x: 0.2, y: 0.91),
                            endPoint: UnitPoint(x: 0.81, y: 0.11)
                        )
                    )
                    .blur(radius: 31)
                    .opacity(0.29)
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
