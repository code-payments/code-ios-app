//
//  MnemonicPhraseTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class MnemonicPhraseTests: XCTestCase {
    
    private let words12 = "picnic ridge embody task harvest mystery hat daughter fan attend say goddess".components(separatedBy: " ")
    private let words24 = "actual beyond joy vessel envelope flat demand panda dish kit unable toy jelly crater happy mesh sing cactus begin guard where gas office try".components(separatedBy: " ")
    
    // MARK: - Init -
    
    func test12Words() {
        let phrase = MnemonicPhrase(words: words12)
        
        XCTAssertNotNil(phrase)
        XCTAssertEqual(phrase?.kind, .words12)
    }
    
    func test24Words() {
        let phrase = MnemonicPhrase(words: words24)
        
        XCTAssertNotNil(phrase)
        XCTAssertEqual(phrase?.kind, .words24)
    }
    
    func testInvalidNumberWords() {
        let words1 = "actual beyond joy vessel envelope flat demand panda dish kit unable toy jelly crater happy mesh sing cactus begin guard where gas office".components(separatedBy: " ")
        let words2 = "actual beyond joy".components(separatedBy: " ")
        let words3 = "".components(separatedBy: " ")
        
        let phrase1 = MnemonicPhrase(words: words1)
        let phrase2 = MnemonicPhrase(words: words2)
        let phrase3 = MnemonicPhrase(words: words3)
        
        XCTAssertNil(phrase1)
        XCTAssertNil(phrase2)
        XCTAssertNil(phrase3)
    }
    
    // MARK: - Base64 -
    
    func test12WordsBase64Encoding() {
        let phrase = MnemonicPhrase(words: words12)!
        
        let base64 = phrase.base64EncodedEntropy
        let data = Data(base64Encoded: base64)!
        XCTAssertEqual(data.hexEncodedString(), "a4373121ef069724da61be52c1d2ffb2")
    }
    
    func test24WordsBase64Encoding() {
        let phrase = MnemonicPhrase(words: words24)!
        
        let base64 = phrase.base64EncodedEntropy
        let data = Data(base64Encoded: base64)!
        XCTAssertEqual(data.hexEncodedString(), "02e2b9e27984bcb10e8cfb3f2f5fb173377c651a3c5ec944005133afa4c02667")
    }
    
    func test12WordBase64Decoding() {
        let phrase = MnemonicPhrase(base64EncodedEntropy: "pDcxIe8GlyTaYb5SwdL/sg==")
        XCTAssertEqual(phrase?.words, words12)
    }
    
    func test24WordBase64Decoding() {
        let phrase = MnemonicPhrase(base64EncodedEntropy: "AuK54nmEvLEOjPs/L1+xczd8ZRo8XslEAFEzr6TAJmc=")
        XCTAssertEqual(phrase?.words, words24)
    }
    
    func testDecodeInvalidBase64() {
        let phrase = MnemonicPhrase(base64EncodedEntropy: "$Jk&")
        XCTAssertNil(phrase)
    }
    
    func testDecodeInvalidData() {
        let phrase = MnemonicPhrase(base64EncodedEntropy: "dGhpcyBpcyBpbnZhbGlkIGJhc2U2NCBkYXRh")
        XCTAssertNil(phrase)
    }
}
