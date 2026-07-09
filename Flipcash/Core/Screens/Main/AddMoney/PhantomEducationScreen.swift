//
//  PhantomEducationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.phantom-education")

/// "Add Money With Phantom" pre-flight — the root of the Phantom deposit flow.
struct PhantomEducationScreen: View {

    @Environment(WalletConnection.self) private var walletConnection

    /// Called once the wallet is connected.
    let onConnected: () -> Void

    @State private var isConnecting = false
    @State private var dialogItem: DialogItem?
    @State private var connectTask: Task<Void, Never>?

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 24) {
                Spacer()

                PhantomHero()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Add money with Phantom using Solana USDC")

                VStack(spacing: 8) {
                    Text("Add Money With Phantom")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Add money using Solana USDC in Phantom. Simply connect your wallet and confirm the transaction.")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)

                Spacer()

                Button(action: connect) {
                    if isConnecting {
                        HStack(spacing: 8) {
                            ProgressView().progressViewStyle(.circular)
                            Text("Connecting…")
                        }
                    } else {
                        Text("Connect Your Phantom Wallet")
                    }
                }
                .buttonStyle(.filled)
                .disabled(isConnecting)
            }
            .padding(20)
        }
        .navigationTitle("Add Money")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
        // A late Phantom round-trip must not navigate after the user leaves,
        // and an abandoned handshake would hold `pendingConnect` hostage.
        .onDisappear { connectTask?.cancel() }
    }

    private func connect() {
        let operation = PhantomDepositOperation(walletConnection: walletConnection)
        connectTask = Task {
            isConnecting = true
            defer { isConnecting = false }
            do {
                try await operation.connect()
                onConnected()
            } catch is CancellationError {
                // User backed out mid-connect — silent.
            } catch DepositError.userCancelled {
                // User rejected the connect in Phantom — silent.
            } catch let DepositError.externalRejected(title, subtitle) {
                dialogItem = .error(title: title, subtitle: subtitle)
            } catch {
                logger.error("Phantom connect failed unexpectedly", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error)
                dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again later")
            }
        }
    }
}

// MARK: - Hero

private struct PhantomHero: View {
    var body: some View {
        HStack(spacing: 16) {
            BadgedIcon(icon: Image.asset(.buyPhantom))

            Image(systemName: "plus")
                .foregroundStyle(Color.textMain)
                .font(.system(size: 20, weight: .medium))

            BadgedIcon(
                icon: Image.asset(.buyUSDC),
                badge: Image.asset(.buySolana)
            )
        }
    }
}
