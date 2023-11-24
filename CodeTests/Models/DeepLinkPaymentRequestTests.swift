//
//  DeepLinkPaymentRequestTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2023-09-11.
//

import XCTest
@testable import CodeServices
@testable import Code

class DeepLinkPaymentRequestTests: XCTestCase {
    
    func testDecode() throws {
        let json = """
        {
          "mode": "payment",
          "currency": "usd",
          "destination": "E8otxw1CVX9bfyddKu3ZB3BVLa4VVF9J7CTPdnUwT9jR",
          "amount": 0.25,
          "clientSecret": "9rSkG4cUdx7D1AW",
          "confirmParams": {
            "success": {
              "url": "https://example.com/success"
            },
            "cancel": {
              "url": "https://example.com/cancel"
            }
          }
        }
        """
        
        let request = try JSONDecoder().decode(DeepLinkPaymentRequest.self, from: Data(json.utf8))
        
        XCTAssertEqual(request.mode, .payment)
        XCTAssertEqual(request.fiat, Fiat(currency: .usd, amount: 0.25))
        XCTAssertEqual(request.clientSecret, Base58.toBytes("9rSkG4cUdx7D1AW").data)
        XCTAssertEqual(request.destination, PublicKey(base58: "E8otxw1CVX9bfyddKu3ZB3BVLa4VVF9J7CTPdnUwT9jR")!)
        XCTAssertEqual(request.successURL?.absoluteString, "https://example.com/success")
        XCTAssertEqual(request.cancelURL?.absoluteString, "https://example.com/cancel")
    }
    
    func testDecodeNoParams() throws {
        let json = """
        {
          "mode": "payment",
          "currency": "usd",
          "destination": "E8otxw1CVX9bfyddKu3ZB3BVLa4VVF9J7CTPdnUwT9jR",
          "amount": 0.25,
          "clientSecret": "9rSkG4cUdx7D1AW",
          "confirmParams": {
            "cancel": {}
          }
        }
        """
        
        let request = try JSONDecoder().decode(DeepLinkPaymentRequest.self, from: Data(json.utf8))
        
        XCTAssertEqual(request.mode, .payment)
        XCTAssertEqual(request.fiat, Fiat(currency: .usd, amount: 0.25))
        XCTAssertEqual(request.clientSecret, Base58.toBytes("9rSkG4cUdx7D1AW").data)
        XCTAssertEqual(request.destination, PublicKey(base58: "E8otxw1CVX9bfyddKu3ZB3BVLa4VVF9J7CTPdnUwT9jR")!)
        XCTAssertNil(request.successURL)
        XCTAssertNil(request.cancelURL)
    }
    
    func testEncode() throws {
        let request = DeepLinkPaymentRequest(
            mode: .payment,
            fiat: Fiat(currency: .usd, amount: 0.25),
            destination: PublicKey(base58: "E8otxw1CVX9bfyddKu3ZB3BVLa4VVF9J7CTPdnUwT9jR")!,
            clientSecret: Base58.toBytes("9rSkG4cUdx7D1AW").data,
            successURL: URL(string: "https://example.com/success")!,
            cancelURL: URL(string: "https://example.com/cancel")!
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let json = try encoder.encode(request)
        
        let decodedRequest = try JSONDecoder().decode(DeepLinkPaymentRequest.self, from: json)
        
        XCTAssertEqual(decodedRequest.mode, request.mode)
        XCTAssertEqual(decodedRequest.fiat, request.fiat)
        XCTAssertEqual(decodedRequest.clientSecret, request.clientSecret)
        XCTAssertEqual(decodedRequest.destination, request.destination)
        XCTAssertEqual(decodedRequest.successURL, request.successURL)
        XCTAssertEqual(decodedRequest.cancelURL, request.cancelURL)
    }
}
