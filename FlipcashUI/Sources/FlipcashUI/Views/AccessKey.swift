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
            .fill(Color.clear)
            .aspectRatio(0.607, contentMode: .fit)
            .background(
                LinearGradient(
                    gradient: Gradient(stops: [
                        Gradient.Stop(color: Color(r: 4,  g: 32, b: 5),  location: 0.0),
                        Gradient.Stop(color: Color(r: 12, g: 41, b: 26), location: 0.57),
                        Gradient.Stop(color: Color(r: 0,  g: 70, b: 2),  location: 0.65),
                        Gradient.Stop(color: Color(r: 0,  g: 26, b: 12), location: 1.00),
                    ]),
                    startPoint: UnitPoint(x: -0.5, y: 1.0),
                    endPoint:   UnitPoint(x: 1.35,  y: 0.15)
                )
                .scaleEffect(1.3)
                .overlay {
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0)
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 200
                    )
                }
                .blur(radius: 20)
            )
            .overlay(
                ZStack {
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
