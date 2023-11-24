//
//  ActionTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class ActionTests: XCTestCase {
    
    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    
    private lazy var organizer = Organizer(mnemonic: mnemonic)
    
    private let nonce      = PublicKey(base58: "JDwJWHij1E75GVAAcMUPkwDgC598wRdF4a7d76QX895S")!
    private let blockhash  = PublicKey(base58: "BXLEqnSJxMHvEJQHRMSbsFQGDpBn891BpQo828xejbi1")!
    private let treasury   = PublicKey(base58: "Ddk7k7zMMWsp8fZB12wqbiADdXKQFWfwUUsxSo73JaQ9")!
    private let recentRoot = PublicKey(base58: "2sDAFcEZkLd3mbm6SaZhifctkyB4NWsp94GMnfDs1BfR")!
    
    // MARK: - Signatures -
    
    func testSignatureProvidedByCloseDormantAccount() throws {
        var action = ActionWithdraw(
            kind: .closeDormantAccount(.outgoing),
            cluster: organizer.tray.outgoing.cluster,
            destination: .mock
        )
        
        XCTAssertNil(try? action.signatures())
        
        action.serverParameter = .basicConfig
        
        XCTAssertEqual(try action.signatures().count, 1)
    }
    
    func testSignatureProvidedByNoPrivacyWithdraw() throws {
        var action = ActionWithdraw(
            kind: .noPrivacyWithdraw(10),
            cluster: organizer.tray.outgoing.cluster,
            destination: .mock
        )
        
        XCTAssertNil(try? action.signatures())
        
        action.serverParameter = .basicConfig
        
        XCTAssertEqual(try action.signatures().count, 1)
    }
    
    func testSignatureProvidedByTempPrivacyTransfer() throws {
        var action = ActionTransfer(
            kind: .tempPrivacyTransfer,
            intentID: .mock,
            amount: 1,
            source: organizer.tray.cluster(for: .bucket(.bucket1)),
            destination: .mock
        )
        
        XCTAssertNil(try? action.signatures())
        
        action.serverParameter = ServerParameter(
            actionID: 0,
            parameter: .tempPrivacy(
                .init(
                    treasury: treasury,
                    recentRoot: recentRoot
                )
            ),
            configs: [
                .init(
                    nonce: nonce,
                    blockhash: blockhash
                )
            ]
        )
        
        XCTAssertEqual(try action.signatures().count, 1)
    }
    
    func testSignatureProvidedByTempPrivacyExchange() throws {
        var action = ActionTransfer(
            kind: .tempPrivacyExchange,
            intentID: .mock,
            amount: 1,
            source: organizer.tray.cluster(for: .bucket(.bucket1)),
            destination: .mock
        )
        
        XCTAssertNil(try? action.signatures())
        
        action.serverParameter = .tempPrivacy
        
        XCTAssertEqual(try action.signatures().count, 1)
    }
    
    func testSignatureProvidedByNoPrivacyTransfer() throws {
        var action = ActionTransfer(
            kind: .noPrivacyTransfer,
            intentID: .mock,
            amount: 1,
            source: organizer.tray.cluster(for: .bucket(.bucket1)),
            destination: .mock
        )
        
        XCTAssertNil(try? action.signatures())
        
        action.serverParameter = .tempPrivacy
        
        XCTAssertEqual(try action.signatures().count, 1)
    }
    
    func testSignatureProvidedByCloseEmptyAccount() throws {
        var action = ActionCloseEmptyAccount(
            type: .incoming,
            cluster: organizer.tray.incoming.cluster
        )
        
        XCTAssertNil(try? action.signatures())
        
        action.serverParameter = .basicConfig
        
        XCTAssertEqual(try action.signatures().count, 1)
    }
    
    func testSignatureProvidedByPrivacyUpgrade() throws {
        var action = ActionPrivacyUpgrade(
            source: organizer.tray.incoming.cluster,
            originalActionID: 0,
            originalCommitmentStateAccount: leaf,
            originalAmount: 1,
            originalNonce: nonce,
            originalRecentBlockhash: blockhash,
            treasury: treasury
        )
        
        XCTAssertNil(try? action.signatures())
        
        action.serverParameter = .privacyUpgrade
        
        // Only validates that signatures are provided
        // and merkle proof is valid but doesn't verify
        // any other server parameters
        
        XCTAssertEqual(try action.signatures().count, 1)
    }
    
    // MARK: - No Signatures -
    
    func testNoSignatureProvidedByOpenAccount() throws {
        var action = ActionOpenAccount(
            owner: organizer.ownerKeyPair.publicKey,
            type: .outgoing,
            accountCluster: organizer.tray.outgoing.cluster
        )
        
        XCTAssertEqual(try action.signatures().count, 0)
        
        action.serverParameter = .basicConfig
        
        XCTAssertEqual(try action.signatures().count, 0)
    }
}

// MARK: - ServerParameter -

extension ServerParameter {
    static let basicConfig: ServerParameter = ServerParameter(
        actionID: 0,
        parameter: nil,
        configs: [
            .init(
                nonce: PublicKey(base58: "JDwJWHij1E75GVAAcMUPkwDgC598wRdF4a7d76QX895S")!,
                blockhash: PublicKey(base58: "BXLEqnSJxMHvEJQHRMSbsFQGDpBn891BpQo828xejbi1")!
            )
        ]
    )
    
    static let tempPrivacy: ServerParameter = ServerParameter(
        actionID: 0,
        parameter: .tempPrivacy(
            .init(
                treasury: PublicKey(base58: "Ddk7k7zMMWsp8fZB12wqbiADdXKQFWfwUUsxSo73JaQ9")!,
                recentRoot: PublicKey(base58: "2sDAFcEZkLd3mbm6SaZhifctkyB4NWsp94GMnfDs1BfR")!
            )
        ),
        configs: [
            .init(
                nonce: PublicKey(base58: "JDwJWHij1E75GVAAcMUPkwDgC598wRdF4a7d76QX895S")!,
                blockhash: PublicKey(base58: "BXLEqnSJxMHvEJQHRMSbsFQGDpBn891BpQo828xejbi1")!
            )
        ]
    )
    
    static let privacyUpgrade: ServerParameter = ServerParameter(
        actionID: 0,
        parameter: .permanentPrivacyUpgrade(
            .init(
                newCommitment: .mock,
                newCommitmentTranscript: .mock,
                newCommitmentDestination: .mock,
                newCommitmentAmount: 1,
                merkleRoot: root,
                merkleProof: proof
            )
        ),
        configs: [
            .init(
                nonce: PublicKey(base58: "JDwJWHij1E75GVAAcMUPkwDgC598wRdF4a7d76QX895S")!,
                blockhash: PublicKey(base58: "BXLEqnSJxMHvEJQHRMSbsFQGDpBn891BpQo828xejbi1")!
            )
        ]
    )
}

// MARK: - Merkle Tree -

private let leaf = PublicKey(base58: "2ocuvgy8ETZp9WDaEy4rpYz2QyeZ7JAiEvXKbW5rKcd4")!
private let root = Hash(base58: "9EuLAJgnMpEq8wmQUFTNxgYJG2FkAPAGCUhrNK447Uox")!
private let proof = [
    "4DEt3CHLarXBy74hiJf5t74HmKfTw5DeLK2nzTLFv3Pq",
    "73uNXKLpHkTgc9ubvyRXTGaNUh19TUx8M9bN4PNTn544",
    "2QH34Bqm89sadRqpz1U5M3Cd34xxNLnTHdxzn4LA3EKU",
    "AaySpzaCsgyTVVgUA9bNTNC6sGsws7sTYNyz2oFAe1gT",
    "BFHDwqjAPupY4PoJn5Lvx7t9mQrXy6iGnTS7NuRyrEav",
    "BFy4XgE4j8NW5PxzDMkH7FWXZcMuFb9zoVSBqdjxm21A",
    "B5Lvj9Zdrynu2DGjYXGmxKxRbvmVFtYoGLyqrzZFymXo",
    "GEspB8aMfyV4Hmtt7fGmFXsZ5QWrbBUSfPeDT3dXS7gG",
    "FuVPGmTwWZayoWt4th2dv8X9xEmRrLvqTbdAXXfRi6Ei",
    "CbTZ7BrcBUsmGEjUqxrjkvDkKNRRJHrjF9tTb3mLmMWb",
    "GEoigbUN6rsrrpRdNi5rJgX2YDXmE6gDsLYevSchzcg4",
    "Gb2zXSV9vxhPkem6PrW45rPiEy9dbJ9nFg7ixQEV4JYh",
    "Bb2r8JJdExSAasR38yuTJu2XHRZEGHRxCR71MrJ6nW1z",
    "5zTGsTA9vmzGYwVYeD3MDcehybca93prZRdjVqRzZQ6y",
    "BbH8JeD3emXYkNw3DvLERM3hMPXhgCEqcU132hSo2uH7",
    "F9re8k2sX2BVGX8WqRBGyiZ2aPvvRj4s62jmtgM73hmT",
    "DGFU6XD6eYi3GtVAwYBP4d2DUYv1BGiquijQH6HXLLi4",
    "8TaNzgiEAP4VoXkBjb1toiZ9fw84RhqezdYt3RhNXR3u",
    "BnF8qb2kYZxFHtmqWircb1Di33XTQc8TV17oFwi1tZ4u",
    "BBNfGrQ7cKBcZgQmqCgw45s9QLkx41qcTjYwrn7tAtoM",
    "Dkf4Fpukx558idi6XwnEx9aAu8GLDzYUC3eN7hQQxPsJ",
    "72BxCoqc9cnQvqEZmqzLcZH7VyMBjJFj3R47D8gpV8WL",
    "BSVw2t3RwN4ab9Zpd68pwLqwHVecgHvacZB28QgNQ3L",
    "7YvGe21SSF93mZoyPsgVF6dD78YWCkVwSff9a4EdE3aj",
    "9wZwjy3V8827XZeeE4CxZgXU5WsRGCfcRYHkaPtB7QGb",
    "GQb7NMsiEfwVWxuLgn7Tev1KEZSs4ASayUiULjACtxNv",
    "Wpb4nF5rc9GpSbWXPUNwA31bemJp61HexerhUx97H8B",
    "HwXMPKHXQoBQkM533yqatDbaY3HLDapUWVGVWUv6366a",
    "Wom44oATBqSD7SZpBwHRmkXhKV4qsC7SnneGTLKhvdN",
    "3xmn2hQdDSKN1ompFNh6AwnQBucWK7Z8mJPyXJzTpLb4",
    "HQ5WDTtCvL14aa16UZJStZVVCTcoYbiUayzzBFm8e97r",
    "Af6F2xzEKyjuiy7wjukatK9BzW42K7vXekkZq9C7W3K",
    "ECS1Mcvt2pYJxYkMDNAp4sNjQq4SadsL3KeJx59ATLbo",
    "5B2C3uLH4TvrrriZgo5UbfQwDVbeqqtd7NPwaujfipAd",
    "DLd8jX9r1o57SaBgnqzextfBHb7aSGdL98t3EzhiKXjC",
    "2cz8R5HYZXs5PKhXXXr562go49A4d5gor42Khejz8K2A",
    "B8ucJEMrosxPoSnnBgMbkcmsGWoqusaaheATT8UFa7AF",
    "D7JCQL3FMGkoqfvvP9TBzzirTeNQDHbUYAxA9Di6pkQm",
    "7fiWLao84havAULW9y5mRDpAqCDSFp2hRmDfN7xQWdWk",
    "9SCyBETC2xV1yk44voyQ7MED4SSURpNsuu6MNY12KndN",
    "FQKnR4ngeSet5UfWyzXsf7RFU4QN83T9C5xSJWcHcZVX",
    "DzN3txNccgTDG58PWfgkx9wBuVPShTp1VTrPyHkvnbpq",
    "4cCa2Zen5gn83AJmAgn3mZE3NodVaYaMZM4UykQcTXyy",
    "7XDMh3UsVHVomz4MmsSPcKtEkSwxGA4S5ypUb5t2Dvmv",
    "6VoqDc2CWeg158GDuQTeerh1VWHRFbcjrKo2VeiiXAD7",
    "5uGA5QbthCBe5QiY3BwaqfnwwfJgVahZc8WHPFXwBV2m",
    "AAV7TTewgfmN6FHW3oV3ad3Q6KKcdbP6ijt7SUThD2bN",
    "AD2GHkMgEmtRFWi6HLpZeHKAeRAZUnGPF7h4mVbeUj7o",
    "By3ScwWYWdZAcFXo6V68cRH6kSbdqtUMgNVdnSNevgb5",
    "C2RCxm7ZSd9A2fXEvJguBYNK6oUdVrMSCHB3k2JxBKek",
    "FHvwmz1bJqm6SfeBLriNhSh8wuwEJc4KDxi2PpVfQtqg",
    "R29HU9mCjih74wRWLbW3nXLcUAbEJAqKUrpXENSbziS",
    "AvNJa3vqawjfrGmqKPybWQa4V42uyiigUgchT4gHt5Gf",
    "CozYPv4cdVeRb5QWCrtuVJk3f2rHJeAFD9ZtQjHLqyyW",
    "BeLz3Yqv2ikvQkmH2mxXYGHgvo93Ns77hStxSjuA8UsZ",
    "H4tEGNHHcCLbA963wtzJxsZVuEdrpQwrBBnmWcBAhChs",
    "CUmSAsfdvnJTUkWLA8chums2ffyveiRNkNVu3t6as6N7",
    "62djLqbyFJz3iJiY4NkWvio46dMfP291cWfZ44wdeDgE",
    "4JjYv9v3z2YoBrMCsmXE6abpm5bNTKwuJp99rjoTdmPF",
    "JB7wk6DDiYKjzasvHPpySd2aCjh1UX5adD5eZgazwEUM",
    "3fCTfZwwMipFUpvbXbcDBBtwuo23hmuTJMYaVECWwNTP",
    "CZ94cA7JHBb4a8mqN9xEJquPNX1TxKqL3cBQms6yfgTr",
    "8PxPosHkG5Q6VBnhiimJaH88yPYt6ZDp4szMBfaVTLun",
].map { PublicKey(base58: $0)! }
