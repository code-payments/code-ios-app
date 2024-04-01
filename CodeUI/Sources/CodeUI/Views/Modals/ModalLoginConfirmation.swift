//
//  ModalLoginConfirmation.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

/// Modal to confirm a login
public struct ModalLoginConfirmation: View {
    
    public let domain: Domain
    public let primaryAction: String
    public let secondaryAction: String
    public let successAction: ThrowingAction
    public let dismissAction: VoidAction
    public let cancelAction: VoidAction
    
    // MARK: - Init -
    
    public init(domain: Domain, primaryAction: String, secondaryAction: String, successAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.domain = domain
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.successAction = successAction
        self.dismissAction = dismissAction
        self.cancelAction = cancelAction
    }
    
    // MARK: - Body -
    
    public var body: some View {
        SheetView(edge: .bottom, backgroundColor: .black) {
            VStack(spacing: 10) {
                
                Text(domain.displayTitle)
                    .font(.appDisplaySmall)
                
                VStack {
                    SwipeControl(
                        style: .black,
                        text: primaryAction,
                        action: {
                            try await successAction()
                        },
                        completion: {
                            try await Task.delay(seconds: 1) // Checkmark delay
                            dismissAction()
                        }
                    )
                    
                    CodeButton(
                        style: .subtle,
                        title: secondaryAction,
                        action: {
                            cancelAction()
                        }
                    )
                    .padding(.bottom, -20)
                }
                .padding(.top, 10)
            }
            .padding(20)
            .padding(.top, 5)
            .foregroundColor(.textMain)
            .font(.appTextMedium)
        }
    }
}
