//
//  TransactionSigning.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// External-wallet transaction signing surface used by `PhantomFundingOperation`.
/// Conformers handshake with the wallet, deliver USDC→USDF sign requests, and
/// publish the callback events the operation consumes.
protocol TransactionSigning: AnyObject {

    /// Stream of deeplink callbacks (`signed`, `userCancelled`, `failed`).
    /// Operations consume this for the lifetime of a sign request.
    var deeplinkEvents: AsyncStream<WalletConnection.DeeplinkEvent> { get }

    /// Opens the wallet's connect deeplink and suspends until it returns.
    /// Throws `CancellationError` on local cancel and
    /// `WalletConnectionError.userCancelledConnect` when the user dismissed
    /// the wallet's connect prompt.
    func handshake() async throws

    /// Builds and forwards a USDC→USDF sign request to the wallet. The
    /// signed transaction is delivered later via `deeplinkEvents`.
    func sendUsdcToUsdfSignRequest(
        usdc: FlipcashCore.TokenAmount,
        fundingSwapId: SwapId,
        displayName: String
    ) async throws
}

extension WalletConnection: TransactionSigning {}
