import Testing
import Foundation
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("GoldBarSceneHost", .timeLimit(.minutes(1)))  // a non-firing SCNView.prepare must fail loudly, not hang the run
struct GoldBarSceneHostTests {

    private final class Owner {}

    private static func key(_ stamp: String) -> GoldBarTextureStore.Key {
        .init(payload: .placeholder35, stampLines: [stamp], serial: "TEST")
    }

    @Test("Adoption returns one pooled view across presentations and tracks the applied key")
    func adopt_poolsOneView() async {
        let host = GoldBarSceneHost(store: GoldBarTextureStore())
        let a = Owner(), b = Owner()
        let first = await host.adopt(key: Self.key("$1"), tuning: .standard, token: ObjectIdentifier(a))
        let second = await host.adopt(key: Self.key("$2"), tuning: .standard, token: ObjectIdentifier(b))
        #expect(first != nil)
        #expect(first === second)
        #expect(host.appliedKey == Self.key("$2"))
    }

    @Test("A stale owner's release is ignored")
    func release_staleToken_isIgnored() async {
        let host = GoldBarSceneHost(store: GoldBarTextureStore())
        let a = Owner(), b = Owner()
        _ = await host.adopt(key: Self.key("$1"), tuning: .standard, token: ObjectIdentifier(a))
        _ = await host.adopt(key: Self.key("$1"), tuning: .standard, token: ObjectIdentifier(b))
        host.release(token: ObjectIdentifier(a))
        #expect(host.ownerToken == ObjectIdentifier(b))
        host.release(token: ObjectIdentifier(b))
        #expect(host.ownerToken == nil)
    }
}
