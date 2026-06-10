import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("AccountInfoService account resolution")
struct AccountInfoServiceTests {

    @Test("OK response with no accounts resolves to accountNotInList")
    func emptyResponse_returnsAccountNotInList() {
        let response = Ocp_Account_V1_GetTokenAccountInfosResponse()

        let result = AccountInfoService.accountInfo(in: response, type: .giftCard)

        #expect(result == .failure(.accountNotInList))
    }

    @Test("OK response without the requested account type resolves to accountNotInList")
    func missingRequestedType_returnsAccountNotInList() {
        var response = Ocp_Account_V1_GetTokenAccountInfosResponse()
        response.tokenAccountInfos = [
            "primary": makeTokenAccountInfo(accountType: .primary),
        ]

        let result = AccountInfoService.accountInfo(in: response, type: .giftCard)

        #expect(result == .failure(.accountNotInList))
    }

    @Test("OK response containing the requested account type resolves to the parsed account")
    func matchingType_returnsParsedAccount() throws {
        let address = try PublicKey(Data(repeating: 1, count: 32))
        let mint    = try PublicKey(Data(repeating: 2, count: 32))
        let owner   = try PublicKey(Data(repeating: 3, count: 32))

        var response = Ocp_Account_V1_GetTokenAccountInfosResponse()
        response.tokenAccountInfos = [
            "giftCard": makeTokenAccountInfo(
                accountType: .remoteSendGiftCard,
                address: address,
                mint: mint,
                owner: owner
            ),
        ]

        let result = AccountInfoService.accountInfo(in: response, type: .giftCard)

        let account = try result.get()
        #expect(account.address == address)
        #expect(account.mint == mint)
        #expect(account.owner == owner)
        #expect(account.authority == owner)
        #expect(account.quarks == 1_000_000)
        #expect(account.balanceSource == .blockchain)
        #expect(account.managementState == .locked)
        #expect(account.blockchainState == .exists)
        #expect(account.claimState == .notClaimed)
    }

    // MARK: - Fixture helpers

    private func makeTokenAccountInfo(
        accountType: Ocp_Common_V1_AccountType,
        address: PublicKey? = nil,
        mint: PublicKey? = nil,
        owner: PublicKey? = nil
    ) -> Ocp_Account_V1_TokenAccountInfo {
        var info = Ocp_Account_V1_TokenAccountInfo()
        info.accountType     = accountType
        info.address         = (address ?? .mock).solanaAccountID
        info.mint            = (mint ?? .mock).solanaAccountID
        info.owner           = (owner ?? .mock).solanaAccountID
        info.authority       = (owner ?? .mock).solanaAccountID
        info.balance         = 1_000_000
        info.balanceSource   = .blockchain
        info.managementState = .locked
        info.blockchainState = .exists
        info.claimState      = .notClaimed
        return info
    }
}
