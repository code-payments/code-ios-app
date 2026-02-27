//
//  URLSanitizationTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@Suite("URL Sanitization for Analytics")
struct URLSanitizationTests {

    // MARK: - Fragments are stripped

    @Test("Login deeplink strips entropy fragment")
    func loginDeeplink() {
        let url = URL(string: "flipcash://login#e=HQPkfAZjgpGGANQfUNPKvW")!
        #expect(url.sanitizedForAnalytics == "flipcash://login")
    }

    @Test("Login universal link strips entropy fragment")
    func loginUniversalLink() {
        let url = URL(string: "https://app.flipcash.com/login#e=HQPkfAZjgpGGANQfUNPKvW")!
        #expect(url.sanitizedForAnalytics == "https://app.flipcash.com/login")
    }

    @Test("Cash link deeplink strips entropy fragment")
    func cashLinkDeeplink() {
        let url = URL(string: "flipcash://c#e=5Kd3NBUAdUnhyzenEwVLy6pj")!
        #expect(url.sanitizedForAnalytics == "flipcash://c")
    }

    @Test("Cash link universal link strips entropy fragment")
    func cashLinkUniversalLink() {
        let url = URL(string: "https://send.flipcash.com/c/#/e=5Kd3NBUAdUnhyzenEwVLy6pj")!
        #expect(url.sanitizedForAnalytics == "https://send.flipcash.com/c/")
    }

    // MARK: - Query parameters are stripped

    @Test("Verify email deeplink strips all query parameters")
    func verifyEmailDeeplink() {
        let url = URL(string: "flipcash://verify?code=123456&email=user@example.com")!
        #expect(url.sanitizedForAnalytics == "flipcash://verify")
    }

    @Test("Verify email universal link strips all query parameters")
    func verifyEmailUniversalLink() {
        let url = URL(string: "https://app.flipcash.com/verify?code=123456&email=user@example.com&clientData=abc")!
        #expect(url.sanitizedForAnalytics == "https://app.flipcash.com/verify")
    }

    @Test("Query parameters with tracking info are stripped")
    func trackingQueryParams() {
        let url = URL(string: "flipcash://something?source=push&ref=campaign123")!
        #expect(url.sanitizedForAnalytics == "flipcash://something")
    }

    // MARK: - Path is preserved

    @Test("Token deeplink preserves public mint in path")
    func tokenDeeplink() {
        let mint = "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25"
        let url = URL(string: "flipcash://token/\(mint)")!
        #expect(url.sanitizedForAnalytics == "flipcash://token/\(mint)")
    }

    @Test("Token universal link preserves public mint in path")
    func tokenUniversalLink() {
        let mint = "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25"
        let url = URL(string: "https://app.flipcash.com/token/\(mint)")!
        #expect(url.sanitizedForAnalytics == "https://app.flipcash.com/token/\(mint)")
    }

    // MARK: - Combined

    @Test("URL with both fragment and query strips both")
    func fragmentAndQuery() {
        let url = URL(string: "flipcash://verify?email=secret@test.com#e=entropy123")!
        #expect(url.sanitizedForAnalytics == "flipcash://verify")
    }
}
