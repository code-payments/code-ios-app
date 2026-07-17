import Testing
@testable import FlipcashCore
import FlipcashAPI

@Suite("UserFlags.preferredOnrampUsdcLiquidityPool")
struct UserFlagsUsdcLiquidityPoolTests {

    @Test(
        "Maps preferredOnRampUsdcLiquidityPool from the proto",
        arguments: [
            (Flipcash_Account_V1_UserFlags.UsdcLiquidityPool.unknownUsdcLiquidityPool, UserFlags.UsdcLiquidityPool.unknown),
            (.flipcash, .flipcash),
            (.coinbaseStableSwapper, .coinbaseStableSwapper),
            (.UNRECOGNIZED(99), .unknown),
        ]
    )
    func preferredOnrampUsdcLiquidityPool_mapsFromProto(
        proto: Flipcash_Account_V1_UserFlags.UsdcLiquidityPool,
        expected: UserFlags.UsdcLiquidityPool
    ) {
        let flags = UserFlags(Flipcash_Account_V1_UserFlags.with { $0.preferredOnRampUsdcLiquidityPool = proto })
        #expect(flags.preferredOnrampUsdcLiquidityPool == expected)
    }

    @Test("Unset proto defaults to unknown")
    func unsetProto_defaultsToUnknown() {
        let flags = UserFlags(Flipcash_Account_V1_UserFlags())
        #expect(flags.preferredOnrampUsdcLiquidityPool == .unknown)
    }
}
