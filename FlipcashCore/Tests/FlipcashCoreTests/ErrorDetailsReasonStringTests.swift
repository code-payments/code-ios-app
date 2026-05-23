import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("ErrorDetails reasonString extraction")
struct ErrorDetailsReasonStringTests {

    @Test(
        "reasonStrings collects every non-empty reason in order, ignoring other detail types",
        arguments: [
            (details: [] as [Ocp_Transaction_V1_ErrorDetails], expected: [] as [String]),
            (details: [.reasonString("only")], expected: ["only"]),
            (details: [.reasonString("first"), .reasonString("second")], expected: ["first", "second"]),
            (details: [.reasonString(""), .reasonString("kept")], expected: ["kept"]),
            (details: [.reasonString(""), .reasonString("")], expected: []),
            (details: [.denied(code: .unspecified, reason: "ignored")], expected: []),
            (
                details: [
                    .reasonString("a"),
                    .denied(code: .unspecified, reason: "ignored"),
                    .reasonString("b")
                ],
                expected: ["a", "b"]
            ),
        ]
    )
    func reasonStrings_filtersAndOrders(details: [Ocp_Transaction_V1_ErrorDetails], expected: [String]) {
        #expect(details.reasonStrings == expected)
    }

    @Test(
        "firstReasonString returns the first non-empty reason or nil",
        arguments: [
            (details: [] as [Ocp_Transaction_V1_ErrorDetails], expected: String?.none),
            (details: [.reasonString("here")], expected: .some("here")),
            (details: [.reasonString("")], expected: .none),
            (details: [.reasonString(""), .reasonString("second")], expected: .some("second")),
            (details: [.denied(code: .unspecified, reason: "ignored")], expected: .none),
        ]
    )
    func firstReasonString_matchesFirstNonEmpty(details: [Ocp_Transaction_V1_ErrorDetails], expected: String?) {
        #expect(details.firstReasonString == expected)
    }
}
