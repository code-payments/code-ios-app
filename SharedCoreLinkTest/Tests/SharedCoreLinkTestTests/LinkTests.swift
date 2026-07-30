import XCTest
import SharedCore

/// Proves the KMP-produced XCFramework links and its exported Kotlin symbols resolve & are callable
/// from Swift. If the framework failed to link, this target would not compile/run.
final class LinkTests: XCTestCase {

    /// The marker object — confirms the framework is linked and a Kotlin `object` bridges to Swift.
    func testMarkerSymbolLinks() {
        XCTAssertEqual(SharedCore.shared.version, "0.0.1-beachhead")
    }

    /// The exported `:libs:network:jwt` types — a data class + sealed interface case, constructed and
    /// read from Swift, proving the in-place-compiled sources are usable across the boundary.
    func testJwtTypesExported() {
        let endpoint = JwtSecuredEndpoint(
            provider: ApiProviderCoinbase.shared,
            scheme: "https",
            host: "api.coinbase.com",
            path: "/v2",
            method: "GET"
        )
        XCTAssertEqual(endpoint.host, "api.coinbase.com")
        XCTAssertEqual(endpoint.method, "GET")
        XCTAssertTrue(endpoint.provider is ApiProviderCoinbase)
    }
}
