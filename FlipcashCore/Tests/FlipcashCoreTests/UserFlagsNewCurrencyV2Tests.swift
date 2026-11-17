import Testing
@testable import FlipcashCore
import FlipcashAPI

@Suite("UserFlags.newCurrencyV2 amounts")
struct UserFlagsNewCurrencyV2Tests {

    @Test("Populates from proto in USDF quarks")
    func newCurrencyV2Amounts_populateFromProto() {
        let proto = Flipcash_Account_V1_UserFlags.with {
            $0.newCurrencyPurchaseAmount = 5_000_000
            $0.newCurrencyFeeAmount = 1_000_000
            $0.newCurrencyV2PurchaseAmount = 7_000_000
            $0.newCurrencyV2FeeAmount = 2_000_000
        }

        let flags = UserFlags(proto)

        #expect(flags.newCurrencyV2PurchaseAmount.quarks == 7_000_000)
        #expect(flags.newCurrencyV2PurchaseAmount.mint == .usdf)
        #expect(flags.newCurrencyV2FeeAmount.quarks == 2_000_000)
        #expect(flags.newCurrencyV2FeeAmount.mint == .usdf)
        // The v1 amounts keep their own fields.
        #expect(flags.newCurrencyPurchaseAmount.quarks == 5_000_000)
        #expect(flags.newCurrencyFeeAmount.quarks == 1_000_000)
    }

    @Test("Zero value is preserved verbatim")
    func newCurrencyV2Amounts_zeroPreserved() {
        let flags = UserFlags(Flipcash_Account_V1_UserFlags())

        #expect(flags.newCurrencyV2PurchaseAmount.quarks == 0)
        #expect(flags.newCurrencyV2PurchaseAmount.mint == .usdf)
        #expect(flags.newCurrencyV2FeeAmount.quarks == 0)
        #expect(flags.newCurrencyV2FeeAmount.mint == .usdf)
    }
}
