//
//  DeepLinkRequestTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2023-09-11.
//

import XCTest
@testable import CodeServices
@testable import Code

class DeepLinkRequestTests: XCTestCase {
    
    func testDecodePaymentRequest() throws {
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
        
        let request = try JSONDecoder().decode(DeepLinkRequest.self, from: Data(json.utf8))
        
        XCTAssertEqual(request.mode, .payment)
        XCTAssertEqual(request.clientSecret, Base58.toBytes("9rSkG4cUdx7D1AW").data)
        XCTAssertEqual(request.paymentRequest?.fiat, Fiat(currency: .usd, amount: 0.25))
        XCTAssertEqual(request.paymentRequest?.destination, PublicKey(base58: "E8otxw1CVX9bfyddKu3ZB3BVLa4VVF9J7CTPdnUwT9jR")!)
        XCTAssertEqual(request.confirmParameters.successURL?.absoluteString, "https://example.com/success")
        XCTAssertEqual(request.confirmParameters.cancelURL?.absoluteString, "https://example.com/cancel")
    }
    
    func testDecodePaymentRequestNoParams() throws {
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
        
        let request = try JSONDecoder().decode(DeepLinkRequest.self, from: Data(json.utf8))
        
        XCTAssertEqual(request.mode, .payment)
        XCTAssertEqual(request.clientSecret, Base58.toBytes("9rSkG4cUdx7D1AW").data)
        XCTAssertEqual(request.paymentRequest?.fiat, Fiat(currency: .usd, amount: 0.25))
        XCTAssertEqual(request.paymentRequest?.destination, PublicKey(base58: "E8otxw1CVX9bfyddKu3ZB3BVLa4VVF9J7CTPdnUwT9jR")!)
        XCTAssertNil(request.confirmParameters.successURL)
        XCTAssertNil(request.confirmParameters.cancelURL)
    }
    
    func testDecodeLoginRequest() throws {
        let json = """
        {
            "mode": "login",
            "login": {
                "verifier": "5TSdPcPLe9CovF5ZK8gfv1kmSpHc9GuWkaDUK2sqC33X",
                "domain": "getcode.com"
            },
            "confirmParams": {
                "success": {
                    "url": "https://example.com/success"
                },
                "cancel": {
                    "url": "https://example.com/cancel"
                }
            },
            "locale": "en",
            "clientSecret": "9rSkG4cUdx7D1AW"
        }
        """
        
        let request = try JSONDecoder().decode(DeepLinkRequest.self, from: Data(json.utf8))
        
        XCTAssertEqual(request.mode, .login)
        XCTAssertEqual(request.clientSecret, Base58.toBytes("9rSkG4cUdx7D1AW").data)
        XCTAssertEqual(request.loginRequest?.verifier, PublicKey(base58: "5TSdPcPLe9CovF5ZK8gfv1kmSpHc9GuWkaDUK2sqC33X")!)
        XCTAssertEqual(request.loginRequest?.domain, Domain("getcode.com"))
        
        XCTAssertNil(request.paymentRequest)
        
        XCTAssertEqual(request.confirmParameters.successURL?.absoluteString, "https://example.com/success")
        XCTAssertEqual(request.confirmParameters.cancelURL?.absoluteString, "https://example.com/cancel")
    }
    
    func testCompleteRequest() throws {
        let json = """
        {
            "mode": "login",
            "currency": "usd",
            "destination": "E8otxw1CVX9bfyddKu3ZB3BVLa4VVF9J7CTPdnUwT9jR",
            "amount": 0.25,
            "clientSecret": "9rSkG4cUdx7D1AW",
            "login": {
                "verifier": "5TSdPcPLe9CovF5ZK8gfv1kmSpHc9GuWkaDUK2sqC33X",
                "domain": "getcode.com"
            },
            "confirmParams": {
                "success": {
                    "url": "https://example.com/success"
                },
                "cancel": {
                    "url": "https://example.com/cancel"
                }
            },
            "locale": "en",
            "clientSecret": "9rSkG4cUdx7D1AW"
        }
        """
        
        let request = try JSONDecoder().decode(DeepLinkRequest.self, from: Data(json.utf8))
        
        XCTAssertEqual(request.mode, .login)
        XCTAssertEqual(request.clientSecret, Base58.toBytes("9rSkG4cUdx7D1AW").data)
        
        XCTAssertEqual(request.paymentRequest?.fiat, Fiat(currency: .usd, amount: 0.25))
        XCTAssertEqual(request.paymentRequest?.destination, PublicKey(base58: "E8otxw1CVX9bfyddKu3ZB3BVLa4VVF9J7CTPdnUwT9jR")!)
        
        XCTAssertEqual(request.loginRequest?.verifier, PublicKey(base58: "5TSdPcPLe9CovF5ZK8gfv1kmSpHc9GuWkaDUK2sqC33X")!)
        XCTAssertEqual(request.loginRequest?.domain, Domain("getcode.com"))
        
        XCTAssertEqual(request.confirmParameters.successURL?.absoluteString, "https://example.com/success")
        XCTAssertEqual(request.confirmParameters.cancelURL?.absoluteString, "https://example.com/cancel")
    }
}
