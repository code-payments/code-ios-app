import Foundation
import Testing
@testable import FlipcashCore

@Suite("SubstitutionApplier")
struct SubstitutionApplierTests {

    @Test("Replaces a single placeholder with the resolution")
    func singlePlaceholder() {
        let result = SubstitutionApplier.apply(
            template: "{0} joined Flipcash",
            resolutions: ["Alex"]
        )
        #expect(result == "Alex joined Flipcash")
    }

    @Test("Replaces multiple positional placeholders")
    func multiplePlaceholders() {
        let result = SubstitutionApplier.apply(
            template: "{0} sent {1} a payment",
            resolutions: ["Alex", "Sam"]
        )
        #expect(result == "Alex sent Sam a payment")
    }

    @Test("Replaces each occurrence of a repeated placeholder")
    func repeatedPlaceholder() {
        let result = SubstitutionApplier.apply(
            template: "{0} and {0} are the same person",
            resolutions: ["Alex"]
        )
        #expect(result == "Alex and Alex are the same person")
    }

    @Test("Uses the fallback string when a resolution is nil")
    func nilResolutionUsesFallback() {
        let result = SubstitutionApplier.apply(
            template: "{0} joined Flipcash",
            resolutions: [nil]
        )
        #expect(result == "Someone you know joined Flipcash")
    }

    @Test("Mixed nil and non-nil resolutions")
    func mixedNilAndResolved() {
        let result = SubstitutionApplier.apply(
            template: "{0} sent {1} a payment",
            resolutions: ["Alex", nil]
        )
        #expect(result == "Alex sent Someone you know a payment")
    }

    @Test("Templates without placeholders are returned unchanged")
    func noPlaceholders() {
        let result = SubstitutionApplier.apply(
            template: "Send them cash",
            resolutions: ["ignored"]
        )
        #expect(result == "Send them cash")
    }

    @Test("Placeholders without a matching index remain in place")
    func placeholdersWithoutMatchingIndex() {
        let result = SubstitutionApplier.apply(
            template: "{0} and {1} and {2}",
            resolutions: ["Alex"]
        )
        #expect(result == "Alex and {1} and {2}")
    }

    @Test("Output never contains an E.164 even when resolutions are nil")
    func neverLeaksE164() {
        let result = SubstitutionApplier.apply(
            template: "{0} joined Flipcash",
            resolutions: [nil]
        )
        let phoneRegex = /\+\d{6,15}/
        #expect(result.firstMatch(of: phoneRegex) == nil)
    }
}
