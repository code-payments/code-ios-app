//
//  RestrictedScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-11-26.
//

import SwiftUI
import CodeServices
import CodeUI

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
            Analytics.open(screen: .restricted)
            ErrorReporting.breadcrumb(.restrictedScreen)
        }
    }
}

extension RestrictedScreen {
    enum Kind {
        
        case timelockAccountUnlocked
        case accessRestricted
        
        var title: String {
            switch self {
            case .timelockAccountUnlocked:
                return Localized.Error.Title.timelockUnlocked
            case .accessRestricted:
                return Localized.Title.accessExpired
            }
        }
        
        var description: String {
            switch self {
            case .timelockAccountUnlocked:
                return Localized.Error.Description.timelockUnlocked
            case .accessRestricted:
                return Localized.Subtitle.accessExpiredDescription
            }
        }
    }
}

// MARK: - Previews -

struct RestrictedScreen_Previews: PreviewProvider {
    static var previews: some View {
        RestrictedScreen(kind: .accessRestricted)
            .preferredColorScheme(.dark)
    }
}
