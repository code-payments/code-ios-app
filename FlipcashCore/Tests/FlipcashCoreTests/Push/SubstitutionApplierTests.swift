import Foundation
import Testing
@testable import FlipcashCore

@Suite("SubstitutionApplier")
struct SubstitutionApplierTests {

    @Test(
        "Replaces {i} placeholders against the resolution table",
        arguments: [
            ("{0} joined Flipcash",              ["Alex"],                    "Alex joined Flipcash"),
            ("{0} sent {1} a payment",           ["Alex", "Sam"],             "Alex sent Sam a payment"),
            ("{0} and {0} are the same person",  ["Alex"],                    "Alex and Alex are the same person"),
            ("{0} sent you cash",                ["(747) 217-6923"],          "(747) 217-6923 sent you cash"),
            ("Send them cash",                   ["ignored"],                 "Send them cash"),
            ("{0} and {1} and {2}",              ["Alex"],                    "Alex and {1} and {2}"),
        ] as [(String, [String], String)]
    )
    func apply(template: String, resolutions: [String], expected: String) {
        #expect(SubstitutionApplier.apply(template: template, resolutions: resolutions) == expected)
    }
}
