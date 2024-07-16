//
//  ProgramDerivedAccountTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class ProgramDerivedAccountTests: XCTestCase {
    
    func testTimelockDerivation() {
        let owner = PublicKey(base58: "BuAprBZugjXG6QRbRQN8QKF8EzbW5SigkDuyR9KtqN5z")!
        let derivedAccounts = TimelockDerivedAccounts(owner: owner)
        
        XCTAssertEqual(derivedAccounts.owner.base58, owner.base58)
        XCTAssertEqual(derivedAccounts.state.publicKey.base58, "7Ema8Z4gAUWegampp2AuX4cvaTRy3VMwJUq8LMJshQTV")
        XCTAssertEqual(derivedAccounts.state.bump, 254)
        XCTAssertEqual(derivedAccounts.vault.publicKey.base58, "3538bYdWoRXUgBbyAyvG3Zemmawh75nmCQEvWc9DfKFR")
        XCTAssertEqual(derivedAccounts.vault.bump, 255)
    }
    
    func testLegacyTimelockDerivation() {
        let owner = PublicKey(base58: "8XfsstyiyT4rCY8ydYthXLisgPHHZFXVtJbcRSsebkWo")!
        let derivedAccounts = TimelockDerivedAccounts(owner: owner)
        
        XCTAssertEqual(derivedAccounts.owner.base58, owner.base58)
        XCTAssertEqual(derivedAccounts.state.publicKey.base58, "BsJs1qFrhJU6QZp3yniAkLfECA898a8yTxbJhVsY9rW2")
        XCTAssertEqual(derivedAccounts.state.bump, 254)
        XCTAssertEqual(derivedAccounts.vault.publicKey.base58, "Aqo1xaEUQqtVLcz2Q6sL5u2YwMaAJygTDeSWf7nEEWWN")
        XCTAssertEqual(derivedAccounts.vault.bump, 250)
    }
    
    func testCommitmentDerivation() throws {
        let treasury    = PublicKey(base58: "3HR2k4etyHtBgHCAisRQ5mAU1x3GxWSgmm1bHsNzvZKS")!
        let destination = PublicKey(base58: "A1WsiTaL6fPei2xcqDPiVnRDvRwpCjne3votXZmrQe86")!
        let recentRoot  = Hash(base58: "BvtnzMe2CSunpGoYnvK6YZut1Jg41yaPBDGdJToPQrqy")!
        let transcript  = Hash(base58: "91aPsVLa6xCcVfC9FozexaMK8TgKCUZMkj4k6yPy2q4S")!
        
        let derivedAccounts = SplitterCommitmentAccounts(
            treasury: treasury,
            destination: destination,
            recentRoot: recentRoot,
            transcript: transcript,
            amount: 1
        )
        
        XCTAssertEqual(derivedAccounts.treasury, treasury)
        XCTAssertEqual(derivedAccounts.destination, destination)
        XCTAssertEqual(derivedAccounts.recentRoot, recentRoot)
        XCTAssertEqual(derivedAccounts.transcript, transcript)
        
        XCTAssertEqual(derivedAccounts.state.publicKey.base58, "4vF8wWhuUSPTmUWPRvNcB5aPNzDvjCYBhyizpG6VFNi6")
        XCTAssertEqual(derivedAccounts.state.bump, 247)
        XCTAssertEqual(derivedAccounts.vault.publicKey.base58, "7BXkxmuwH4GGm48gPWMWqHnLYX7NwrtGPUtfHKnhgMmZ")
        XCTAssertEqual(derivedAccounts.vault.bump, 254)
    }
    
    func testTranscriptHash() {
        let transcript = SplitterTranscript(
            intentID: PublicKey(base58: "4roBdWPCqbuqr4YtPavfi7hTAMdH52RXMDgKhqQ4qvX6")!,
            actionID: 1,
            amount: 40,
            source: PublicKey(base58: "GNVyMgwkFQvm3YLuJdEVW4xEoqDYnixVaxVYT59frGWW")!,
            destination: PublicKey(base58: "Cia66LdCtvfJ6G5jjmLtNoFx5JvWr3uNv2iaFvmSS9gW")!
        )
        
        XCTAssertEqual(transcript.transcriptHash.base58, "5Yh4E953ePoBWe8w78FgMqEjiNmtCQi2ct9BTc2shuLi")
    }
    
    func testPreSwapStateDerivation() {
        let owner = PublicKey(base58: "8XfsstyiyT4rCY8ydYthXLisgPHHZFXVtJbcRSsebkWo")!
        let source = PublicKey(base58: "5nNBW1KhzHVbR4NMPLYPRYj3UN5vgiw5GrtpdK6eGoce")!
        let destination = PublicKey(base58: "9Rgx4kjnYZBbeXXgbbYLT2FfgzrNHFUShDtp8dpHHjd2")!
        let nonce = PublicKey(base58: "3SVPEF5HDcKLhVfKeAnbH5Azpyeuk2yyVjEjZbz4VhrL")!
        
        let derivedAccounts = PreSwapStateAccount(
            owner: owner, // Not used in derivation, just mock
            source: source,
            destination: destination,
            nonce: nonce
        )
        
        XCTAssertEqual(derivedAccounts.state.publicKey.base58, "Hh338LHJhkzPbDisGt5Lge8qkgc3RExvH7BdmKgnRQw9")
    }
}
