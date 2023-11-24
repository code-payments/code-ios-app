//
//  KinText.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct KinText: View {
    
    private let text: String
    private let format: Format
    
    // MARK: - Init -
    
    public init(_ text: String, format: Format = .regular) {
        self.text = text
        self.format = format
    }
    
    // MARK: - Body -
    
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing(for: format)) {
            if !text.isEmpty {
                Image.symbol(symbol(for: format))
                Text(text)
                    .minimumScaleFactor(0.5)
            }
        }
    }
    
    private func spacing(for format: Format) -> CGFloat {
        switch format {
        case .regular:
            return 5
        case .large:
            return 3
        }
    }
    
    private func symbol(for format: Format) -> Symbol {
        switch format {
        case .regular:
            return .hexSmall
        case .large:
            return .hexLarge
        }
    }
}

// MARK: - Format -

extension KinText {
    public enum Format {
        case regular
        case large
    }
}

// MARK: - Previews -

struct KinText_Previews: PreviewProvider {
    
    static let fonts: [Font] = [
        .largeTitle,
        .title,
        .headline,
        .body,
        .callout,
        .subheadline,
        .footnote,
        .caption,
    ]
    
    static var previews: some View {
        VStack {
            Spacer()
            ForEach(fonts, id: \.self) { font in
                KinText("1,000,000")
                    .font(font.weight(.ultraLight))
            }
            Spacer()
            ForEach(fonts, id: \.self) { font in
                KinText("1,000,000")
                    .font(font.weight(.regular))
            }
            Spacer()
            ForEach(fonts, id: \.self) { font in
                KinText("1,000,000")
                    .font(font.weight(.black))
            }
            Spacer()
        }
        .padding(20.0)
    }
}
