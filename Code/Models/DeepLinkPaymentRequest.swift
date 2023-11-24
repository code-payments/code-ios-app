//
//  DeepLinkPaymentRequest.swift
//  Code
//
//  Created by Dima Bart on 2023-09-11.
//

import Foundation
import CodeServices

struct DeepLinkPaymentRequest: Equatable {
    
    let mode: Mode
    let fiat: Fiat
    let destination: PublicKey
    let clientSecret: Data
    let successURL: URL?
    let cancelURL: URL?
    
    init(mode: Mode, fiat: Fiat, destination: PublicKey, clientSecret: Data, successURL: URL?, cancelURL: URL?) {
        self.mode = mode
        self.fiat = fiat
        self.destination = destination
        self.clientSecret = clientSecret
        self.successURL = successURL
        self.cancelURL = cancelURL
    }
}

// MARK: - Mode -

extension DeepLinkPaymentRequest {
    enum Mode: String, Hashable, Equatable, Codable {
        case payment
        case donation
    }
}

// MARK: - Codable -

extension DeepLinkPaymentRequest: Codable {
    
    enum RequestKeys: CodingKey {
        case mode
        case currency
        case destination
        case amount
        case clientSecret
        case successURL
        case cancelURL
        case confirmParams
    }
    
    enum ConfirmParamKeys: CodingKey {
        case success
        case cancel
    }
    
    enum URLKeys: CodingKey {
        case url
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RequestKeys.self)
        
        var successURL: URL?
        var cancelURL: URL?
        
        let mode              = try container.decode(Mode.self,    forKey: .mode)
        let currencyCode      = try container.decode(String.self,  forKey: .currency)
        let amount            = try container.decode(Decimal.self, forKey: .amount)
        let destinationString = try container.decode(String.self,  forKey: .destination)
        let secret            = try container.decode(String.self,  forKey: .clientSecret)
        
        let confirmParams = try container.nestedContainer(keyedBy: ConfirmParamKeys.self, forKey: .confirmParams)
        
        if let success = try? confirmParams.nestedContainer(keyedBy: URLKeys.self, forKey: .success) {
            successURL = try success.decodeIfPresent(URL.self, forKey: .url)
        }
        
        if let cancel = try? confirmParams.nestedContainer(keyedBy: URLKeys.self, forKey: .cancel) {
            cancelURL = try cancel.decodeIfPresent(URL.self, forKey: .url)
        }
        
        guard let currency = CurrencyCode(currencyCode: currencyCode) else {
            throw Error.invalidCurrencyCode
        }
        
        guard let destination = PublicKey(base58: destinationString) else {
            throw Error.invalidDestinationAddress
        }
        
        let fiat = Fiat(currency: currency, amount: amount)
        
        let clientSecret = Base58.toBytes(secret).data
        
        guard clientSecret.count == 11 else {
            throw Error.invalidClientSecret
        }
     
        self.init(
            mode: mode,
            fiat: fiat,
            destination: destination,
            clientSecret: clientSecret,
            successURL: successURL,
            cancelURL: cancelURL
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RequestKeys.self)
        var params    = container.nestedContainer(keyedBy: ConfirmParamKeys.self, forKey: .confirmParams)
        var success   = params.nestedContainer(keyedBy: URLKeys.self, forKey: .success)
        var cancel    = params.nestedContainer(keyedBy: URLKeys.self, forKey: .cancel)
        
        let currency = fiat.currency
        let amount   = fiat.amount
        let secret   = Base58.fromBytes(clientSecret.bytes)
        
        try container.encode(mode.rawValue,      forKey: .mode)
        try container.encode(currency.rawValue,  forKey: .currency)
        try container.encode(amount,             forKey: .amount)
        try container.encode(destination.base58, forKey: .destination)
        try container.encode(secret,             forKey: .clientSecret)
        try success.encode(successURL,           forKey: .url)
        try cancel.encode(cancelURL,             forKey: .url)
    }
}

extension DeepLinkPaymentRequest {
    enum Error: Swift.Error {
        case invalidCurrencyCode
        case invalidDestinationAddress
        case invalidClientSecret
    }
}
