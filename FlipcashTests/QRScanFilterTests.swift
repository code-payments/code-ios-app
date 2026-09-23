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
        URL(string: "https://flipcash.com/brandon")!,
        URL(string: "https://flipcash.com/3f2504e0-4f89-41d3-9a0c-0305e82c3301")!,
        URL(string: "https://app.flipcash.com/chat/52fba6a9-3940-899e-af16-eddf7c6364b2")!,
    ]

    static let blockedURLs: [URL] = [
        URL(string: "https://app.flipcash.com/login#e=HQPkfAZjgpGGANQfUNPKvW")!,
        URL(string: "https://app.flipcash.com/verify?code=123&email=test@example.com")!,
        URL(string: "https://google.com")!,
        URL(string: "https://app.flipcash.com/chat/52fba6a9-3940-899e-af16-eddf7c6364b2/send")!,
        // A QR code is read off whatever the camera is pointed at, so its host is nobody's
        // promise. `Route` matches on path alone: ungated, a Discord invite scans as a handle
        // and an attacker's `/c/#/e=…` scans as a cash link.
        URL(string: "https://discord.gg/rattlepokemon")!,
        URL(string: "https://t.me/somechannel")!,
        URL(string: "https://evil.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW")!,
        URL(string: "https://send.flipcash.com.evil.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW")!,
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
