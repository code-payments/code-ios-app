//
//  WithdrawViewModel.swift
//  Code
//
//  Created by Dima Bart on 2022-08-04.
//

import UIKit
import CodeServices
import CodeUI

@MainActor
class WithdrawViewModel: ObservableObject {
    
    @Published private(set) var withdrawalButtonState: ButtonState = .normal

    @Published var enteredAmount: String  = ""
    
    @Published var enteredAddress: String = ""
    
    @Published var destinationMetadata: DestinationMetadata?
    
    var amount: KinAmount? {
        KinAmount(
            stringAmount: enteredAmount,
            rate: entryRate
        )?.truncatingQuarks()
    }
    
    var address: PublicKey? {
        PublicKey(base58: enteredAddress)
    }
    
    var resolvedDestination: PublicKey? {
        destinationMetadata?.resolvedDestination
    }
    
    var supportsDecimalEntry: Bool {
        entryRate.currency != .kin
    }
    
    var hasValidAmount: Bool {
        amount != nil && amount!.kin.quarks > 0
    }
    
    var hasSufficientFunds: Bool {
        guard let amount = amount else {
            return false
        }
        
        return hasSufficientFundsToSend(amount: amount)
    }
    
    var shouldShowFormattedKinAmount: KinAmount? {
        if let money = amount, entryRate.currency != .kin {
            return money
        } else {
            return nil
        }
    }
    
    var readyToSend: Bool {
        hasSufficientFunds &&
        amount != nil &&
        address != nil &&
        destinationMetadata?.resolvedDestination != nil &&
        destinationMetadata?.isValid == true
    }
    
    var entryRate: Rate {
        exchange.entryRate
    }
    
    var formattedMaxFiatAmount: String {
        session.currentBalance.formattedFiat(rate: entryRate, truncated: true, showOfKin: true)
    }
    
    var formattedEnteredAmount: String {
        (amount?.kin ?? 0).formattedFiat(rate: entryRate, truncated: false, showOfKin: true)
    }
    
    var formattedEnteredKin: String {
        (amount?.kin ?? 0).formattedTruncatedKin()
    }
    
    var canAttemptPasteAddress: Bool {
        UIPasteboard.general.hasStrings
    }
    
    var currencyRules: KeyPadView.CurrencyRules {
        KeyPadView.CurrencyRules(
            maxIntegerDigits: 9,
            maxDecimalDigits: entryRate.currency == .kin ? 0 : 2
        )
    }
    
    private let session: Session
    private let exchange: Exchange
    private let biometrics: Biometrics
    private let completion: (Bool) -> Void
    
    // MARK: - Init -
    
    init(session: Session, exchange: Exchange, biometrics: Biometrics, completion: @escaping (Bool) -> Void = { _ in }) {
        self.session    = session
        self.exchange   = exchange
        self.biometrics = biometrics
        self.completion = completion
    }
    
    // MARK: - Destination -
    
    func addressDidChange() {
        fetchDestinationMetadataIfNeeded()
    }
    
    private func fetchDestinationMetadataIfNeeded() {
        if let destination = address {
            Task {
                destinationMetadata = await session.fetchDestinationMetadata(destination: destination)
            }
        } else {
            destinationMetadata = nil
        }
    }
    
    // MARK: - Actions -
    
    func resetAddress() {
        enteredAddress = ""
        destinationMetadata = nil
    }
    
    @discardableResult
    func attemptPasteAddressFromClipboard() -> Bool {
        guard
            let string = UIPasteboard.general.string,
            let address = PublicKey(base58: string)
        else {
            return false
        }
        
        enteredAddress = address.base58
        return true
    }
    
    func hasSufficientFundsToSend(amount: KinAmount) -> Bool {
        amount.kin <= session.currentBalance
    }
    
    func withdraw() async throws {
        guard
            let amount = amount,
            let address = destinationMetadata?.resolvedDestination
        else {
            completion(false)
            throw Error.invalidRequirements
        }
        
        if let context = biometrics.verificationContext() {
            guard await context.verify(reason: .withdraw) else {
                completion(false)
                throw Error.biometricsFailed
            }
            try await Task.delay(milliseconds: 500)
        }

        do {
            withdrawalButtonState = .loading
            try await session.withdrawExternally(amount: amount, to: address)
            withdrawalButtonState = .success
            try await Task.delay(seconds: 1)
            
            completion(true)
            
        } catch {
            withdrawalButtonState = .normal
            completion(false)
            throw error
        }
    }
}

extension WithdrawViewModel {
    enum Error: Swift.Error {
        case invalidRequirements
        case biometricsFailed
    }
}

extension KeyPadView.CurrencyRules {

    static func code(hasDecimals: Bool) -> KeyPadView.CurrencyRules {
        KeyPadView.CurrencyRules(
            maxIntegerDigits: 9,
            maxDecimalDigits: hasDecimals ? 2 : 0
        )
    }
}
