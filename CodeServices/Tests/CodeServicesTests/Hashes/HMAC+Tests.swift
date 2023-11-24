//
//  HMAC+Tests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class HMACTests: XCTestCase {
    
    private let key = Data("ed25519 seed".utf8)
    
    func testSHA1() {
        var hmac = HMAC(algorithm: .sha1, key: key)
        hmac.update("water cook crack oval")
        
        XCTAssertEqual(hmac.digestData().hexEncodedString(), "6d72a702f7ba51b64d17bfc6b12dff13604a3f52")
    }
    
    func testSHA224() {
        var hmac = HMAC(algorithm: .sha224, key: key)
        hmac.update("water cook crack oval")
        
        XCTAssertEqual(hmac.digestData().hexEncodedString(), "dab7d6a2791e44d684aa382e5b547078005a1d39d927a7c861327b72")
    }
    
    func testSHA256() {
        var hmac = HMAC(algorithm: .sha256, key: key)
        hmac.update("water cook crack oval")
        
        XCTAssertEqual(hmac.digestData().hexEncodedString(), "c32c43fbabba80443a408b0f14469a9e94d5806d6c7797d73a906702d64efbae")
    }
    
    func testSHA384() {
        var hmac = HMAC(algorithm: .sha384, key: key)
        hmac.update("water cook crack oval")
        
        XCTAssertEqual(hmac.digestData().hexEncodedString(), "4472f80652b5e32e49eb1bc85fd52bcdc4e8053f27b21b30d0dcf7e66f46d039214171179f72661ba282a19ee9d89caf")
    }
    
    func testSHA512() {
        var hmac = HMAC(algorithm: .sha512, key: key)
        hmac.update("water cook crack oval")
        
        XCTAssertEqual(hmac.digestData().hexEncodedString(), "1a550827bc079b0d555ec6a3cd071cfa420c050832661f348dd56dc96fb6d20df9ad68cd8b52ac506de84fc2db9df36aad566dc6adf293c52d2210d406a89b3f")
    }
}
