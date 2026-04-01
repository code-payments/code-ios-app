import Foundation
import Testing
@testable import Flipcash

@Suite("QR Scan Filtering")
struct QRScanFilterTests {

    static let allowedURLs: [URL] = [
        URL(string: "https://send.flipcash.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW")!,
        URL(string: "flipcash://c#e=HQPkfAZjgpGGANQfUNPKvW")!,
        URL(string: "https://app.flipcash.com/token/54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")!,
        URL(string: "flipcash://token/54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")!,
    ]

    static let blockedURLs: [URL] = [
        URL(string: "https://app.flipcash.com/login#e=HQPkfAZjgpGGANQfUNPKvW")!,
        URL(string: "https://app.flipcash.com/verify?code=123&email=test@example.com")!,
        URL(string: "https://google.com")!,
    ]

    @Test("Allowed routes pass QR scan filter", arguments: allowedURLs)
    func allowedRoutes(url: URL) {
        #expect(ScanViewModel.canScanQR(url: url))
    }

    @Test("Blocked routes rejected by QR scan filter", arguments: blockedURLs)
    func blockedRoutes(url: URL) {
        #expect(!ScanViewModel.canScanQR(url: url))
    }
}
