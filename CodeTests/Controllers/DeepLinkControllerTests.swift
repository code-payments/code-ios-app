//
//  DeepLinkControllerTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2023-04-14.
//

import XCTest
import CodeServices
@testable import Code

@MainActor
class DeepLinkControllerTests: XCTestCase {
    
    private let expectedMnemonic = MnemonicPhrase(base58EncodedEntropy: "CMmaC33f5JpG6cgf2XRCHN")
    
    // MARK: - Login -
    
    func testValidLogin() {
        let controller = deepLinkController()
        let loginURL = URL(string: "https://app.getcode.com/login/#/e=CMmaC33f5JpG6cgf2XRCHN")!

        let action = controller.handle(open: loginURL)
        XCTAssertNotNil(action)
        
        if case .login(let mnemonic) = action!.kind {
            XCTAssertEqual(mnemonic, expectedMnemonic)
        } else {
            XCTFail()
        }
    }
    
    func testValidLegacyLogin() {
        let controller = deepLinkController()
        let loginURL = URL(string: "https://app.getcode.com/login?data=CMmaC33f5JpG6cgf2XRCHN")!

        let action = controller.handle(open: loginURL)
        XCTAssertNotNil(action)
        
        if case .login(let mnemonic) = action!.kind {
            XCTAssertEqual(mnemonic, expectedMnemonic)
        } else {
            XCTFail()
        }
    }
    
    func testInvalidLogins() {
        let controller = deepLinkController()
        
        let invalidLinks = [
            "https://app.getcode.com/login/#/eCMmaC33f5JpG6cgf2XRCHN",
            "https://app.getcode.com/login/#/e=notbase58encodedentropy",
            "https://app.getcode.com/other/#/eCMmaC33f5JpG6cgf2XRCHN",
        ]
        
        invalidLinks.forEach {
            let loginURL = URL(string: $0)!
            let action = controller.handle(open: loginURL)
            XCTAssertNil(action)
        }
    }
    
    // MARK: - Cash -
    
    func testValidCashLink() {
        let controller = deepLinkController()
        
        let validLinks = [
            "https://cash.getcode.com/c/#/e=CMmaC33f5JpG6cgf2XRCHN",
            "https://cash.getcode.com/cash/#/e=CMmaC33f5JpG6cgf2XRCHN",
            "https://app.getcode.com/c/#/e=CMmaC33f5JpG6cgf2XRCHN",
            "https://app.getcode.com/cash/#/e=CMmaC33f5JpG6cgf2XRCHN",
        ]

        let expectedGiftCard = GiftCardAccount(mnemonic: expectedMnemonic)
        
        validLinks.forEach {
            let action = controller.handle(open: URL(string: $0)!)
            XCTAssertNotNil(action)
            
            if case .receiveRemoteSend(let giftCard) = action!.kind {
                XCTAssertEqual(giftCard, expectedGiftCard)
            } else {
                XCTFail()
            }
        }
    }
    
    // MARK: - Utilities -
    
    private func deepLinkController() -> DeepLinkController {
        DeepLinkController(sessionAuthenticator: .mock, abacus: .mock)
    }
}
