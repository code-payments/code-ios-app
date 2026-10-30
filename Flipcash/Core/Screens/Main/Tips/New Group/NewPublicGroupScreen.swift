//
//  NewPublicGroupScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.new-public-group")

/// The "New Community Chat" form: a name, an optional picture, and the balance a member has to hold
/// to get in (node 10127:118014). For ``GroupPrivacy/private`` it is "New Group" (node
/// 11203:65): no balance requirement, and a note on what privacy means instead.
struct NewPublicGroupScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ConversationController.self) private var conversationController
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var model: NewPublicGroupModel
    @State private var isPickingPhoto = false
    @State private var isPickingCurrency = false
    @State private var isEnteringCustomAmount = false
    @State private var dialog: DialogItem?
    @State private var buttonState: ButtonState = .normal

    @FocusState private var isTitleFocused: Bool

    private var session: Session { sessionContainer.session }

    init(privacy: GroupPrivacy = .public) {
        _model = State(initialValue: NewPublicGroupModel(privacy: privacy))
    }

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

                    switch model.privacy {
                    case .public:
                        currencySection
                            .padding(.top, 37)
                        requirementSection
                            .padding(.top, 37)
                    case .private:
                        Text("Only people you approve can join. Messages are end-to-end encrypted.")
                            .font(.default(size: 13, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .accessibilityIdentifier("new-private-group-footnote")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: communityCurrencies, initial: true) { _, currencies in
            model.applyDefaultCurrency(from: currencies)
        }
        .navigationTitle(model.privacy == .private ? "New Group" : "New Community Chat")
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
                // Dollars isn't a community currency.
                excludesUSDF: true,
                // The check follows the requirement's mint, not the wallet's denomination — this
                // screen is picking what the gate weighs, not what the balance is shown in.
                isSelected: { $0.stored.mint == model.currency?.stored.mint }
            ) { balance in
                model.select(balance: balance)
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

    /// The holdings the requirement counts, opening the currency picker (node 11745:1054).
    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Community Currency")

            Group {
                if let balance = model.currency {
                    CommunityCurrencyRow(name: balance.stored.name, action: { isPickingCurrency = true }) {
                        TokenIcon(url: balance.stored.imageURL, monogramID: balance.stored.mint.base58, size: 32)
                    }
                } else {
                    // Reached only by a route that skips the chooser's check, or before balances
                    // load; the design draws no frame for it.
                    CommunityCurrencyRow(name: "Select a Currency", action: { isPickingCurrency = true }) {
                        EmptyView()
                    }
                }
            }
            .disabled(model.isCreating)
            .accessibilityIdentifier("new-group-currency-row")
        }
    }

    private var requirementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Minimum Balance Required")

            presets
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.backgroundRow, in: .rect(cornerRadius: Metrics.buttonRadius))

            if let caption = model.requirementCaption {
                Text(caption)
                    .font(.default(size: 13, weight: .medium))
                    .foregroundStyle(Color.textMain.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("new-group-requirement-caption")
            }

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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.default(size: 17, weight: .bold))
            .foregroundStyle(Color.textMain.opacity(0.5))
            .padding(.horizontal, 12)
    }

    /// A USD-priced minimum as the viewer reads it, in the display currency.
    private func displayed(_ amount: FiatAmount) -> FiatAmount {
        ratesController.displayCurrency.amount(amount)
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(NewPublicGroupModel.presets, id: \.self) { amount in
                AmountPresetButton(isSelected: model.minimumBalance == amount) {
                    model.select(minimumBalance: amount)
                } label: {
                    Text(displayed(amount).formattedDroppingZeroFraction())
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
                    Text(displayed(custom).formattedDroppingZeroFraction())
                } else {
                    Image.system(.ellipsis)
                }
            }
            .accessibilityLabel(
                model.customMinimumBalance.map { "Custom amount, \(displayed($0).formattedDroppingZeroFraction())" }
                    ?? "Custom amount"
            )
            .accessibilityIdentifier("new-group-custom-amount-button")
        }
    }

    /// Shown only once the limit is close enough to explain a disabled Create.
    private static let countdownThreshold = 10

    /// The picker's list, whose first entry is the form's default currency.
    private var communityCurrencies: [ExchangedBalance] {
        session.balances(for: ratesController.rateForBalanceCurrency()).communityCurrencies()
    }

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
                        flipClient: container.flipClient,
                        groupKeys: sessionContainer.groupKeys
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
                // Both privacies land in the chat. A private group's invite card is there, so the
                // host's first job (inviting people) starts from it rather than from the profile.
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
