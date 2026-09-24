//
//  NewPublicGroupScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.new-public-group")

/// The "New Public Group" form: a name, an optional picture, and the balance a member has to hold
/// to get in (node 10127:118014).
struct NewPublicGroupScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ConversationController.self) private var conversationController
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var model = NewPublicGroupModel()
    @State private var isPickingPhoto = false
    @State private var isPickingCurrency = false
    @State private var isEnteringCustomAmount = false
    @State private var dialog: DialogItem?
    @State private var buttonState: ButtonState = .normal

    @FocusState private var isTitleFocused: Bool

    private var session: Session { sessionContainer.session }

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    nameCard

                    // Only once the limit is close enough to explain a disabled Create, matching
                    // the display-name field's countdown.
                    if model.remainingTitleScalars < Self.countdownThreshold {
                        Text("\(model.remainingTitleScalars) characters")
                            .font(.default(size: 13, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }

                    requirementSection
                        .padding(.top, 37)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("New Public Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // The design puts Create in the bar rather than over the content (node
                // 10127:118246), so the form scrolls under a control that stays put.
                Button(action: create) {
                    createLabel
                        .foregroundStyle(.white)
                }
                .prominentButtonStyle()
                // Disabled for every state but `.normal`, so the pill dims behind the spinner and
                // the checkmark and a second tap can't start a second chat.
                .disabled(!canCreate || !buttonState.isNormal)
                .accessibilityIdentifier("new-group-create-button")
            }
        }
        .dialog(item: $dialog)
        .fullScreenCover(isPresented: $isPickingPhoto) {
            ImagePickerWithEditor(
                onImagePicked: model.select(picture:),
                onDismiss: { isPickingPhoto = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isPickingCurrency) {
            SelectCurrencyScreen(
                isPresented: $isPickingCurrency,
                // The check follows the requirement's mint, not the wallet's denomination — this
                // screen is picking what the gate weighs, not what the balance is shown in.
                isSelected: { $0.stored.mint == model.currency.mint },
                listTitle: "Specific Currency"
            ) { balance in
                model.select(balance: balance)
            } header: {
                AllCurrenciesCard(
                    isSelected: model.currency == .all,
                    total: session.totalBalance.usdfValue,
                    requirement: model.minimumBalance,
                    meetsRequirement: model.satisfiesAllCurrencies(
                        session: session,
                        rates: ratesController.cachedRates
                    )
                ) {
                    model.selectAllCurrencies()
                    isPickingCurrency = false
                }
            }
        }
        .sheet(isPresented: $isEnteringCustomAmount) {
            MinimumBalanceAmountSheet(isPresented: $isEnteringCustomAmount) { amount in
                model.select(minimumBalance: amount)
            }
        }
    }

    @ViewBuilder private var createLabel: some View {
        switch buttonState {
        case .normal:
            Text("Create")
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
        case .success, .successText:
            Image.system(.checkmark)
        }
    }

    // MARK: - Form -

    /// The picture and the name, which the design draws as one card rather than as a tile above a
    /// field (node 10127:118271).
    private var nameCard: some View {
        HStack(spacing: 12) {
            GroupPictureTile(image: model.picture)
                .onTapGesture { isPickingPhoto = true }
                .accessibilityIdentifier("new-group-photo-picker")

            TextField("Group Name (Required)", text: $model.title)
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .disabled(model.isCreating)
                .accessibilityIdentifier("new-group-title-field")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundRow, in: .rect(cornerRadius: Metrics.buttonRadius))
    }

    private var requirementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Balance Requirement")
                .font(.default(size: 17, weight: .bold))
                .foregroundStyle(Color.textMain.opacity(0.5))
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 10) {
                mintRow
                presets
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundRow, in: .rect(cornerRadius: Metrics.buttonRadius))

            Text("People won't be able to join this chat if their balance is less than this amount")
                .font(.default(size: 13, weight: .medium))
                .foregroundStyle(Color.textMain.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)

            // The server refuses a chat whose creator is short of its own rules, so say so here
            // rather than spending the round trip to be told.
            if model.rules != nil, !satisfiesOwnRules {
                Text("You need this balance yourself to create the group")
                    .font(.default(size: 13, weight: .medium))
                    .foregroundStyle(Color.textError)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("new-group-self-requirement-warning")
            }
        }
    }

    /// The holdings the requirement counts, opening the currency picker (nodes 10127:118254 and
    /// 10364:1059).
    private var mintRow: some View {
        Button { isPickingCurrency = true } label: {
            HStack(spacing: 4) {
                switch model.currency {
                case .all:
                    AllCurrenciesIcon(size: 20)

                    Text("All Currencies")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)

                case .specific(let balance):
                    RemoteImage(url: balance.stored.imageURL)
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())

                    Text(balance.stored.name)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                }

                Image.system(.chevronDown)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isCreating)
        .accessibilityIdentifier("new-group-currency-row")
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(NewPublicGroupModel.presets, id: \.self) { amount in
                AmountPresetButton(isSelected: model.minimumBalance == amount) {
                    model.select(minimumBalance: amount)
                } label: {
                    Text(amount.formattedDroppingZeroFraction())
                }
            }

            // The fourth slot is the keypad's, and a custom amount has nowhere else to show, so
            // it takes this chip's face — the ellipsis is what an unused slot looks like. Same
            // rule Android's chip row follows.
            AmountPresetButton(isSelected: model.customMinimumBalance != nil) {
                isTitleFocused = false
                isEnteringCustomAmount = true
            } label: {
                if let custom = model.customMinimumBalance {
                    Text(custom.formattedDroppingZeroFraction())
                } else {
                    Image.system(.ellipsis)
                }
            }
            .accessibilityLabel(
                model.customMinimumBalance.map { "Custom amount, \($0.formattedDroppingZeroFraction())" }
                    ?? "Custom amount"
            )
            .accessibilityIdentifier("new-group-custom-amount-button")
        }
    }

    /// Shown only once the limit is close enough to explain a disabled Create.
    private static let countdownThreshold = 10

    private var satisfiesOwnRules: Bool {
        model.satisfiesOwnRules(session: session, rates: ratesController.cachedRates)
    }

    private var canCreate: Bool {
        model.canCreate(session: session, rates: ratesController.cachedRates)
    }

    // MARK: - Create -

    private func create() {
        guard canCreate else { return }

        isTitleFocused = false
        buttonState = .loading

        Task {
            do {
                let conversation = try await model.create(
                    using: SessionGroupChatCreator(
                        session: session,
                        flipClient: container.flipClient
                    )
                )

                // Seated before the push so the screen it lands on reads the chat out of the store
                // rather than refetching what `StartChat` already returned.
                conversationController.seatCreatedGroup(conversation)

                buttonState = .success
                // Same beat the rest of the app holds its checkmark for.
                try? await Task.delay(milliseconds: 500)

                guard !Task.isCancelled else { return }

                // The whole create flow is replaced rather than stacked under the chat. Back from
                // a group that now exists belongs at the chat list holding it, not at a filled
                // form offering to create it twice or at the picker that opened the form. The
                // chat list is this stack's root, so unwinding to it is the same as popping both.
                router.popToRoot()
                router.push(.tipConversation(conversation.id))

            } catch {
                buttonState = .normal
                handle(error)
            }
        }
    }

    private func handle(_ error: Error) {
        guard !Task.isCancelled else { return }

        switch error {
        case ErrorStartChat.titleModerated(let category):
            logger.info("Group title moderation denied", metadata: ["category": "\(category)"])
            ErrorReporting.captureError(error, reason: "Group title moderation denied")
            dialog = .error(
                title: "This Name is Not Allowed",
                subtitle: "Try a different group name"
            )

        case ErrorStartChat.pictureBlobNotAccepted:
            logger.info("Group picture not accepted")
            ErrorReporting.captureError(error, reason: "Group picture not accepted")
            dialog = .error(
                title: "This Photo Isn't Allowed",
                subtitle: "Try a different photo"
            )

        case ErrorStartChat.rulesNotSatisfied:
            // The client check ran against a balance that has since moved, or against a rate that
            // had not landed. The server is the authority, so its answer is what is shown.
            logger.info("Group creator does not satisfy their own rules")
            ErrorReporting.captureError(error, reason: "Group creator does not satisfy their own rules")
            dialog = .error(
                title: "You Don't Meet This Requirement",
                subtitle: "Lower the minimum balance or add funds"
            )

        case ErrorStartChat.invalidRules:
            logger.error("Group rules rejected as invalid")
            ErrorReporting.captureError(error, reason: "Group rules rejected as invalid")
            dialog = .error(
                title: "This Requirement Isn't Valid",
                subtitle: "Try a different minimum balance"
            )

        case ErrorStartChat.denied:
            logger.info("Group creation denied")
            ErrorReporting.captureError(error, reason: "Group creation denied")
            dialog = .error(
                title: "You Can't Create a Group",
                subtitle: "Try again later"
            )

        case let blobError as ErrorBlob:
            logger.info("Group picture upload failed", metadata: ["error": "\(blobError)"])
            ErrorReporting.captureError(blobError, reason: "Group picture upload failed", userFacing: true)
            dialog = .profilePictureFailed(blobError)

        case let encoderError as ImageEncoderError:
            logger.error("Failed to encode the group picture", metadata: ["error": "\(encoderError)"])
            ErrorReporting.captureError(encoderError, reason: "Failed to encode the group picture")
            dialog = .imageProcessingFailed

        default:
            logger.error("Failed to create group", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to create group")
            dialog = .error(
                title: "Couldn't Create This Group",
                subtitle: "Try again"
            )
        }
    }
}

// MARK: - GroupPictureTile -

/// The group's picture, or the camera tile that stands in for one (node 10127:118272).
private struct GroupPictureTile: View {

    let image: UIImage?

    private static let size: CGFloat = 74

    var body: some View {
        Circle()
            .fill(Color.backgroundRow)
            .frame(width: Self.size, height: Self.size)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image.asset(.camera)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .compositingGroup()
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(Color.white.opacity(0.17)) }
            .contentShape(Circle())
    }
}

// MARK: - AmountPresetButton -

/// One of the minimum-balance presets, or the custom-entry ellipsis beside them (node
/// 10127:118261). The selected one inverts to a white fill.
private struct AmountPresetButton<Label: View>: View {

    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    /// Node 10127:118260 — the preset row is 61pt tall.
    private static var height: CGFloat { 61 }

    var body: some View {
        Button(action: action) {
            label()
                .font(.default(size: 22, weight: .bold))
                .tracking(-0.88)
                // Four chips share the row, so a custom amount wider than a preset shrinks to fit
                // rather than wrapping or clipping.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isSelected ? Color.textAction : Color.textMain)
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .background(
                    isSelected ? Color.action : Color.white.opacity(0.1),
                    in: .rect(cornerRadius: Metrics.buttonRadius)
                )
                .contentShape(.rect(cornerRadius: Metrics.buttonRadius))
        }
        .buttonStyle(.plain)
    }
}
