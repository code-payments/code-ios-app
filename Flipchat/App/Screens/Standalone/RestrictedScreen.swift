//
//  RestrictedScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-11-26.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct RestrictedScreen: View {
    
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    
    private let title: String
    private let description: String
    
    // MARK: - Init -
    
    init(kind: Kind) {
        self.init(
            title: kind.title,
            description: kind.description
        )
    }
    
    private init(title: String, description: String) {
        self.title = title
        self.description = description
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    Text(title)
                        .font(.appTextLarge)
                        .foregroundColor(.textMain)
                    Text(description)
                        .font(.appTextSmall)
                        .foregroundColor(.textSecondary)
                        .padding([.leading, .trailing], 20)
                    Spacer()
                }
                
                Spacer()
                CodeButton(style: .filled, title: Localized.Action.logout) {
                    sessionAuthenticator.logout()
                }
            }
            .multilineTextAlignment(.center)
            .padding(20)
        }
        .onAppear {
            ErrorReporting.breadcrumb(.restrictedScreen)
        }
    }
}

// MARK: - Kind -

extension RestrictedScreen {
    enum Kind {
        
        case timelockAccountUnlocked
        
        var title: String {
            switch self {
            case .timelockAccountUnlocked:
                return Localized.Error.Title.timelockUnlocked
            }
        }
        
        var description: String {
            switch self {
            case .timelockAccountUnlocked:
                return Localized.Error.Description.timelockUnlocked
            }
        }
    }
}

// MARK: - Previews -

#Preview {
    RestrictedScreen(kind: .timelockAccountUnlocked)
        .preferredColorScheme(.dark)
}
