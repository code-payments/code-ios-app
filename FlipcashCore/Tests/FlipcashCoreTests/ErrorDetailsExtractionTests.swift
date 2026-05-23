import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("ErrorDetails reasonStrings extraction")
struct ErrorDetailsReasonStringsTests {

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
}

@Suite("ErrorDetails deniedReasons extraction")
struct ErrorDetailsDeniedReasonsTests {

    @Test(
        "deniedReasons collects every non-empty reason in order, ignoring other detail types",
        arguments: [
            (details: [] as [Ocp_Transaction_V1_ErrorDetails], expected: [] as [String]),
            (details: [.denied(code: .unspecified, reason: "only")], expected: ["only"]),
            (
                details: [
                    .denied(code: .unspecified, reason: "first"),
                    .denied(code: .unspecified, reason: "second")
                ],
                expected: ["first", "second"]
            ),
            (
                details: [
                    .denied(code: .unspecified, reason: ""),
                    .denied(code: .unspecified, reason: "kept")
                ],
                expected: ["kept"]
            ),
            (details: [.denied(code: .unspecified, reason: "")], expected: []),
            (details: [.reasonString("ignored")], expected: []),
            (
                details: [
                    .denied(code: .unspecified, reason: "a"),
                    .reasonString("ignored"),
                    .denied(code: .unspecified, reason: "b")
                ],
                expected: ["a", "b"]
            ),
        ]
    )
    func deniedReasons_filtersAndOrders(details: [Ocp_Transaction_V1_ErrorDetails], expected: [String]) {
        #expect(details.deniedReasons == expected)
    }
}
