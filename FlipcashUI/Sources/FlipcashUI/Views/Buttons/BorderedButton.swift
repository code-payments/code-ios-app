//
//  BorderedButton.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-08-11.
//

import SwiftUI

public struct BorderedButton: View {
    
    public let image: Image?
    public let title: String
    public let subtitle: String?
    public let showChevron: Bool
    public let action: () -> Void
    
    private var strokeColor: Color {
        .lightStroke
    }
    
    private var fillColor: Color {
        .extraLightFill
    }
    
    private var textColor: Color {
        .white.opacity(0.6)
    }
    
    // MARK: - Init -
    
    public init(image: Image?, title: String, subtitle: String?, showChevron: Bool = true, action: @escaping () -> Void) {
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.showChevron = showChevron
        self.action = action
    }
    
    // MARK: - Body -
    
    public var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 16) {
                if let image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22, alignment: .center)
                        .foregroundStyle(Color.textMain)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appTextCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                
                if showChevron {
                    Image.system(.chevronRight)
                        .renderingMode(.template)
                        .font(.appTextBody)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 70)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.boxRadius)
                    .fill(fillColor)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
        }
    }
}

// MARK: - Colors -

private extension Color {
    static let extraLightFill = Color(r: 12, g: 37, b: 24)
    static let lightStroke    = Color.textSecondary.opacity(0.15)
}
