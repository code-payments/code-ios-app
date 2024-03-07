//
//  DeepLinkPaymentRequest.swift
//  Code
//
//  Created by Dima Bart on 2023-09-11.
//

import Foundation
import CodeServices

struct DeepLinkRequest: Equatable {
    
    let mode: Mode
    let clientSecret: Data
    let paymentRequest: PaymentRequest?
    let loginRequest: LoginRequest?
    let confirmParameters: ConfirmParameters
    
    init(mode: Mode, clientSecret: Data, paymentRequest: PaymentRequest?, loginRequest: LoginRequest?, confirmParameters: ConfirmParameters) {
        self.mode = mode
        self.clientSecret = clientSecret
        self.paymentRequest = paymentRequest
        self.loginRequest = loginRequest
        self.confirmParameters = confirmParameters
    }
}

// MARK: - Mode -

extension DeepLinkRequest {
    enum Mode: String, Hashable, Equatable, Codable {
        case payment
        case donation
        case login
    }
}

// MARK: - Types -

extension DeepLinkRequest {
    struct PaymentRequest: Equatable, Hashable {
        let fiat: Fiat
        let destination: PublicKey
        let fees: [Fee]
    }
    
    struct Fee: Equatable, Hashable, Codable {
        let destination: String
        let basisPoints: Int
    }
    
    struct LoginRequest: Equatable, Hashable {
        let verifier: PublicKey
        let domain: Domain
    }
    
    struct ConfirmParameters: Equatable, Hashable {
        let successURL: URL?
        let cancelURL: URL?
    }
}

// MARK: - Codable -

extension DeepLinkRequest: Decodable {
    
    enum RequestKeys: CodingKey {
        case mode
        case clientSecret
        
        case currency
        case destination
        case amount
        case fees
        
        case login
        
        case confirmParams
        case successURL
        case cancelURL
    }
    
    enum ConfirmParamKeys: CodingKey {
        case success
        case cancel
    }
    
    enum LoginKeys: CodingKey {
        case verifier
        case domain
        case clientSecret
    }
    
    enum URLKeys: CodingKey {
        case url
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RequestKeys.self)
        
        let mode   = try container.decode(Mode.self,   forKey: .mode)
        let secret = try container.decode(String.self, forKey: .clientSecret)
        
        let clientSecret = Base58.toBytes(secret).data
        
        // Payment Request
        
        let paymentRequest: PaymentRequest?
        do {
            let currencyCode      = try container.decode(String.self,  forKey: .currency)
            let amount            = try container.decode(Decimal.self, forKey: .amount)
            let destinationString = try container.decode(String.self,  forKey: .destination)
            
            // Optional
            let fees = try container.decodeIfPresent([Fee].self, forKey: .fees)
            
            guard let currency = CurrencyCode(currencyCode: currencyCode) else {
                throw Error.invalidCurrencyCode
            }
            
            guard let destination = PublicKey(base58: destinationString) else {
                throw Error.invalidDestinationAddress
            }
            
            let fiat = Fiat(currency: currency, amount: amount)
            
            paymentRequest = PaymentRequest(
                fiat: fiat,
                destination: destination,
                fees: fees ?? []
            )
            
        } catch {
            // Failed to parse payment request
            paymentRequest = nil
        }
        
        // Login
        
        let loginRequest: LoginRequest?
        do {
            let loginContainer = try container.nestedContainer(keyedBy: LoginKeys.self, forKey: .login)
            let verifierString = try loginContainer.decode(String.self, forKey: .verifier)
            let domainString   = try loginContainer.decode(String.self, forKey: .domain)
            
            guard let verifier = PublicKey(base58: verifierString) else {
                throw Error.invalidVerifier
            }
            
            guard let domain = Domain(domainString) else {
                throw Error.invalidDomain
            }
            
            loginRequest = LoginRequest(
                verifier: verifier,
                domain: domain
            )
            
        } catch {
            // Failed to parse login
            loginRequest = nil
        }
        
        // Confirm Parameters
         
        let confirmParams = try container.nestedContainer(keyedBy: ConfirmParamKeys.self, forKey: .confirmParams)
        
        var successURL: URL?
        var cancelURL: URL?
        
        if let success = try? confirmParams.nestedContainer(keyedBy: URLKeys.self, forKey: .success) {
            successURL = try success.decodeIfPresent(URL.self, forKey: .url)
        }
        
        if let cancel = try? confirmParams.nestedContainer(keyedBy: URLKeys.self, forKey: .cancel) {
            cancelURL = try cancel.decodeIfPresent(URL.self, forKey: .url)
        }
        
        let confirmParameters = ConfirmParameters(
            successURL: successURL,
            cancelURL: cancelURL
        )
        
        self.init(
            mode: mode,
            clientSecret: clientSecret,
            paymentRequest: paymentRequest,
            loginRequest: loginRequest,
            confirmParameters: confirmParameters
        )
    }
}

extension DeepLinkRequest {
    enum Error: Swift.Error {
        case invalidCurrencyCode
        case invalidDestinationAddress
        case invalidVerifier
        case invalidDomain
        case invalidClientSecret
    }
}
