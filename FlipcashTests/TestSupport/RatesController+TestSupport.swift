//
//  RatesController+TestSupport.swift
//  FlipcashTests
//
//  Created by GitHub Copilot on 2026-02-01.
//

import Foundation
import FlipcashCore
@testable import Flipcash

extension RatesController {
    /// Configure entry currency and inject rates for tests.
    func configureTestRates(entryCurrency: CurrencyCode? = nil, rates: [Rate]) {
        if let entryCurrency {
            self.entryCurrency = entryCurrency
        }

        updateRates(rates)
    }
}