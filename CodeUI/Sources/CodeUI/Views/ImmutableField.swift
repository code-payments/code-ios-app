//
//  ImmutableField.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct ImmutableField: View {
    
    private var content: String
    private var state: State?
    private var configuration: Configuration
    
    public init(_ content: String, state: State? = nil, configuration: Configuration = .default) {
        self.content = content
        self.state = state
        self.configuration = configuration
    }
    
    public var body: some View {
        InputContainer {
            HStack(spacing: 2) {
                Group {
                    switch configuration {
                    case .default:
                        Text(content)
                            .truncationMode(.middle)
                            .lineLimit(1)
                    case .kin:
                        KinText(content, format: .large)
                            .truncationMode(.middle)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 26)
                
                if let state = state {
                    Spacer()
                    state.image
                        .renderingMode(.template)
                        .frame(minWidth: 26)
                        .foregroundColor(state.color)
                }
            }
            .padding(15)
            .font(.appTextMedium)
            .foregroundColor(.textMain)
        }
    }
}

// MARK: - State -

extension ImmutableField {
    public enum State: Equatable {
        
        case success(Image)
        case `default`(Image)
        
        var image: Image {
            switch self {
            case .success(let image):
                return image
            case .default(let image):
                return image
            }
        }
        
        var color: Color {
            switch self {
            case .success:
                return .textSuccess
            case .default:
                return .textSecondary
            }
        }
    }
}

// MARK: - Configuration -

extension ImmutableField {
    public enum Configuration {
        case `default`
        case kin
    }
}

// MARK: - Previews -

struct ImmutableField_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                ImmutableField("9xFTcyYWKmU3dXwayxaGCmHrCoWgUrSvqEiJu6i9YD9", state: .default(.system(.doc)))
                ImmutableField("849.99")
                ImmutableField("849.99", configuration: .kin)
            }
            .padding(20)
        }
        .previewLayout(.fixed(width: 400, height: 300))
    }
}
