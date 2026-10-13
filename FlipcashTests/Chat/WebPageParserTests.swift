//
//  WebPageParserTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore

@Suite("WebPageParser")
struct WebPageParserTests {

    private final class BundleToken {}

    struct Page: Decodable, CustomTestStringConvertible {
        struct Expect: Decodable {
            let title: String
            let description: String?
            let imageUrl: String?
            let host: String
        }
        let name: String
        let finalUrl: String
        let html: String
        let expect: Expect?

        var testDescription: String { name }
    }

    private struct Fixture: Decodable { let pages: [Page] }

    static let pages: [Page] = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "link_metadata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let fixture = try? JSONDecoder().decode(Fixture.self, from: data) else { return [] }
        return fixture.pages
    }()

    @Test func fixtureIsLoaded() {
        #expect(!Self.pages.isEmpty)
    }

    @Test(arguments: pages)
    func parsesLikeTheFixture(_ page: Page) throws {
        let finalURL = try #require(URL(string: page.finalUrl))
        let result = WebPageParser.parse(Data(page.html.utf8), finalURL: finalURL)

        guard let expect = page.expect else {
            #expect(result == nil)
            return
        }
        let resolved = try #require(result)
        #expect(resolved.title == expect.title)
        #expect(resolved.description == expect.description)
        #expect(resolved.imageURL?.absoluteString == expect.imageUrl)
        #expect(resolved.host == expect.host)
    }
}
