//
//  AccessKey.swift
//  Flipchat
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeUI
import FlipchatServices

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
            .fill(Color.clear)
            .aspectRatio(0.607, contentMode: .fit)
            .background(
                LinearGradient(
                    gradient: Gradient(stops: [
                        Gradient.Stop(color: Color(r: 35,  g: 22,  b: 88),  location: 0.21),
                        Gradient.Stop(color: Color(r: 68, g: 48, b: 145), location: 0.46),
                        Gradient.Stop(color: Color(r: 148,  g: 94,  b: 206),  location: 0.64),
                    ]),
                    startPoint: UnitPoint(x: 0.19, y: 1),
                    endPoint: UnitPoint(x: 0.88, y: 0.14)
                )
                .scaleEffect(1.3)
                .blur(radius: 20)
            )
            .overlay(
                ZStack {
                    VStack {
                        
                        Image(with: .brandLarge)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 35)
                            
                        Spacer()
                        
                        QRCode(
                            string: url.absoluteString,
                            showLabel: false,
                            codeColor: .white,
                            backgroundColor: .clear
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 130)
                        
                        Spacer()
                        
                        VStack {
                            ForEach(mnemonicGroups, id: \.self) { group in
                                Text(group)
                            }
                        }
                        .font(.appTextAccessKey)
                        .foregroundStyle(Color.textMain)
                    }
                    .padding([.top, .bottom], 60)
                    
                    RadialGradient(
                        gradient: Gradient(stops: [
                            Gradient.Stop(color: Color(r: 255, g: 255, b: 255, o: 0.1), location: 0.0),
                            Gradient.Stop(color: Color(r: 255, g: 255, b: 255, o: 0),   location: 1.0),
                        ]),
                        center: UnitPoint(x: 0.0, y: 0.0),
                        startRadius: 0,
                        endRadius: 300
                    )
                }
            )
            .clipped()
            .cornerRadius(10)
            .drawingGroup()
            .frame(maxWidth: 255)
    }
}

#Preview {
    AccessKey(mnemonic: .generate(.words12), url: URL(string: "https://example.com")!)
}
