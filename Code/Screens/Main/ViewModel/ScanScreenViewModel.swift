//
//  TooltipViewModel.swift
//  Code
//
//  Created by Dima Bart on 2022-09-08.
//

import UIKit
import CodeServices
import CodeUI
import SwiftUI

@MainActor
class TooltipViewModel: ObservableObject {
    
    @Published var tooltipLogoShown: Bool
    
    private let owner: PublicKey
    
    private let accountOlderThan24Hours: Bool
    
    // MARK: - Init -
    
    init(owner: PublicKey) {
        if let description = AccountManager.fetchDescription(for: owner) {
            let delta = Date.now.timeIntervalSince1970 - description.creationDate.timeIntervalSince1970
            self.accountOlderThan24Hours = delta > 60 * 60 * 24
        } else {
            self.accountOlderThan24Hours = false
        }
        
        self.owner = owner
        self.tooltipLogoShown = UserDefaults.tooltipLogoShownDate == nil && accountOlderThan24Hours
        
        clearTooltipLogoShown()
    }
 
    // MARK: - Tooltip -
    
    func markTooltipLogoShown() {
        tooltipLogoShown = false
        UserDefaults.tooltipLogoShownDate = .now
    }
    
    func clearTooltipLogoShown() {
        tooltipLogoShown = true
        UserDefaults.tooltipLogoShownDate = nil
    }
}

extension UserDefaults {
    
    @Defaults(.tooltipLogo)
    fileprivate static var tooltipLogoShownDate: Date?
}
