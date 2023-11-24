//
//  TransactionBuilderTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class TransactionBuilderTests: XCTestCase {
    
    func testCloseDormantAccountTransaction() {
        var (transaction, _) = SolanaTransaction.mockCloseDormantAccount()
        
        let authority   = PublicKey(base58: "Ed3GWPEdMiRXDMf7jU46fRwBF7n6ZZFGN3vH1dYAgME2")!
        let destination = PublicKey(base58: "GEaVZeZ52Jn8xHPy4VKaXsHQ34E6pwfJGuYh8EsYQi6M")!
        let nonce       = PublicKey(base58: "27aoaJKNVtqKXRKQeMdKrtPMqAzcyYH5PGEgQ8x88TMH")!
        let blockhash   = PublicKey(base58: "7mezFVdzzwHfAxXCDo1gSdRTZE8WwQP9sHbAnPjS3AJD")!

        let derivedAccounts = TimelockDerivedAccounts(owner: authority)
        
        let builtTransaction = TransactionBuilder.closeDormantAccount(
            authority: authority,
            timelockDerivedAccounts: derivedAccounts,
            destination: destination,
            nonce: nonce,
            recentBlockhash: blockhash,
            kreIndex: KRE.index
        )
        
        // Remove the signatures before comparison
        transaction.signatures = [.zero, .zero]
        
        XCTAssertEqual(builtTransaction.encode(), transaction.encode())
        XCTAssertEqual(SolanaTransaction(data: builtTransaction.encode())!.encode(), builtTransaction.encode())
    }
    
    func testTransferTransaction() {
        var (transaction, _) = SolanaTransaction.mockPrivateTransfer()
        
        let authority   = PublicKey(base58: "Ddk7k7zMMWsp8fZB12wqbiADdXKQFWfwUUsxSo73JaQ9")!
        let destination = PublicKey(base58: "2sDAFcEZkLd3mbm6SaZhifctkyB4NWsp94GMnfDs1BfR")!
        let nonce       = PublicKey(base58: "H7y8REaqickypzCfke3onJVKbbp8ELmaccFYeLZzJ2Wn")!
        let blockhash   = PublicKey(base58: "HjD8boPVb9pBVMQBdSzUMTt1HKTonwPsC3RibtXw44pK")!
        
        let derivedAccounts = TimelockDerivedAccounts(owner: authority)
        
        let builtTransaction = TransactionBuilder.transfer(
            timelockDerivedAccounts: derivedAccounts,
            destination: destination,
            amount: 2,
            nonce: nonce,
            recentBlockhash: blockhash,
            kreIndex: KRE.index
        )
        
        // Remove the signatures before comparison
        transaction.signatures = [.zero, .zero]
        
        XCTAssertEqual(builtTransaction.encode(), transaction.encode())
        XCTAssertEqual(SolanaTransaction(data: builtTransaction.encode())!.encode(), builtTransaction.encode())
    }
    
    func testCloseEmptyAccount() {
        var (transaction, _) = SolanaTransaction.mockCloseEmptyAccount()
        
        let authority   = PublicKey(base58: "CiMF8M1VD8HYbWHoX3BhKk4XDcLgzpvz4QJsdULWU84")!
        let nonce       = PublicKey(base58: "JDwJWHij1E75GVAAcMUPkwDgC598wRdF4a7d76QX895S")!
        let blockhash   = PublicKey(base58: "BXLEqnSJxMHvEJQHRMSbsFQGDpBn891BpQo828xejbi1")!
        
        let derivedAccounts = TimelockDerivedAccounts(owner: authority)
        
        let builtTransaction = TransactionBuilder.closeEmptyAccount(
            timelockDerivedAccounts: derivedAccounts,
            maxDustAmount: 1,
            nonce: nonce,
            recentBlockhash: blockhash
        )
        
        // Remove the signatures before comparison
        transaction.signatures = [.zero, .zero]
        
        XCTAssertEqual(builtTransaction.encode(), transaction.encode())
        XCTAssertEqual(SolanaTransaction(data: builtTransaction.encode())!.encode(), builtTransaction.encode())
    }
}
