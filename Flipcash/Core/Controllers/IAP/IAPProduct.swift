//
//  IAPProduct.swift
//  Code
//
//  Created by Dima Bart on 2025-05-07.
//

enum IAPProduct: String, CaseIterable, Hashable, Equatable {
    
    case createAccount                 = "com.flipcash.iap.createAccount"
//    case createAccountWithWelcomeBonus = "com.flipcash.iap.createAccountWithWelcomeBonus"
    
    static var productIDs: Set<String> {
        Set(allCases.map { $0.rawValue })
    }
}
