//
//  File.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

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
                        Gradient.Stop(color: Color(r: 32, g: 35, b: 36), location: 0.0),
                        Gradient.Stop(color: Color(r: 102, g: 102, b: 121), location: 0.2),
                        Gradient.Stop(color: Color(r: 15, g: 12, b: 31), location: 0.53),
                        Gradient.Stop(color: Color(r: 105, g: 105, b: 132), location: 0.62),
                        Gradient.Stop(color: Color(r: 32, g: 35, b: 36), location: 1.0),
                    ]),
                    startPoint: UnitPoint(x: -0.5, y: 1.0),
                    endPoint: UnitPoint(x: 1.5, y: 0.1)
                )
                .scaleEffect(1.3)
                .blur(radius: 20)
            )
            .overlay(
                ZStack {
                    VStack {
                        CodeBrand(size: .flexible, template: true)
                            .frame(maxWidth: 90)
                            .foregroundColor(.white)
                            
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
                            Gradient.Stop(color: Color(r: 255, g: 255, b: 255, o: 0), location: 1.0),
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
