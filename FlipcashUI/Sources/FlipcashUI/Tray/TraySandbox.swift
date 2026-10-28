//
//  TraySandbox.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if DEBUG
import SwiftUI
import FlipcashCore

/// The tray prototype, standing in for the whole app when launched with `--tray-sandbox`: a
/// static Amount Entry look-alike with a menu of every kind of tray.
///
/// A launch argument for the same reason as the motion sandbox: one `simctl launch` line puts the
/// device on the trays with no sign-in, so a tuning round starts in the same place every time.
/// `--tray-sandbox-open <kind>` opens one kind at launch. DEBUG-only, so it can't ship.
public struct TraySandbox: View {

    /// Whether the app was launched with `--tray-sandbox`, or the tuner's "Tray Behavior/Open tray
    /// sandbox" is on, which holds across launches from the home screen. // LOCAL-TUNER
    @MainActor public static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--tray-sandbox")
            || Tuner.shared.value("Tray Behavior/Open tray sandbox", default: false) // LOCAL-TUNER
    }

    /// Whether the deposit flow plays itself (`--tray-sandbox-autoplay`): open, forward to the end,
    /// back to the root, close, so two recordings differ only by the code under test.
    static var autoplays: Bool {
        ProcessInfo.processInfo.arguments.contains("--tray-sandbox-autoplay")
    }

    /// The kind named after `--tray-sandbox-open`, if any.
    static var requestedKind: TrayKind? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--tray-sandbox-open"), index + 1 < arguments.count else { return nil }
        return TrayKind(rawValue: arguments[index + 1])
    }

    @State private var kind: TrayKind?
    @State private var isShowingInfo = false
    @State private var lastOpened: String?
    @State private var lastDismissed: String?

    /// Creates the sandbox.
    public init() {}

    public var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--tray-sandbox-cross") {
            CrossComparison()
        } else {
            sandbox
        }
    }

    private var sandbox: some View {
        AmountEntryBackdrop(lastDismissed: lastDismissed, open: open)
            // Item-driven: every kind but the info tray.
            .tray(item: $kind, isDismissable: kind?.isDismissable ?? true, onDismiss: { lastDismissed = lastOpened }) { kind in
                kind.tray
            }
            // Bool-driven: the info tray.
            .tray(isPresented: $isShowingInfo, onDismiss: { lastDismissed = lastOpened }) {
                TrayKind.info.tray
            }
            .preferredColorScheme(.dark)
            .task {
                if Self.autoplays {
                    try? await Task.sleep(for: .seconds(1))
                    kind = .depositFlow
                } else if let requested = Self.requestedKind {
                    try? await Task.sleep(for: .seconds(0.5))
                    open(requested)
                }
            }
            // A release in these groups replays nothing rather than stepping the flow.
            .onTunerReplay("Tray Layout") {} // LOCAL-TUNER
            .onTunerReplay("Tray Type") {} // LOCAL-TUNER
            .onTunerReplay("Tray Fill") {} // LOCAL-TUNER
            .onTunerReplay("Tray Behavior") {} // LOCAL-TUNER
            .onTunerReplay("Tray Rows") {} // LOCAL-TUNER
            .onTunerReplay("Tray Amount") {} // LOCAL-TUNER
    }

    private func open(_ kind: TrayKind) {
        lastOpened = kind.name
        switch kind {
        case .info: isShowingInfo = true
        case .decision, .destructive, .error, .success, .form, .list, .depositFlow, .amount, .amountFlow: self.kind = kind
        }
    }
}

// MARK: - Catalog

/// Every kind of tray the app needs, each built the one way the component offers; the Beta
/// Features showcase presents them over Settings.
public enum TrayKind: String, Identifiable, CaseIterable {
    case info
    case decision
    case destructive
    case error
    case success
    case form
    case list
    case depositFlow
    case amount
    case amountFlow

    public var id: String { rawValue }

    /// The kind's name in the sandbox menu.
    public var name: String {
        switch self {
        case .info: "Info, one CTA"
        case .decision: "Decision, no X"
        case .destructive: "Destructive confirm"
        case .error: "Error"
        case .success: "Success, not dismissable"
        case .form: "Text field, CTA states"
        case .list: "List content"
        case .depositFlow: "Multi-step flow"
        case .amount: "Amount"
        case .amountFlow: "Amount, multi-step"
        }
    }

    /// Whether the kind can be dragged or closed away.
    public var isDismissable: Bool {
        switch self {
        case .decision, .success: false
        case .info, .destructive, .error, .form, .list, .depositFlow, .amount, .amountFlow: true
        }
    }

    /// The kind's tray, for `.tray(item:)`.
    @MainActor @ViewBuilder
    public var tray: some View {
        switch self {
        case .info: InfoTray()
        case .decision: DecisionTray()
        case .destructive: DestructiveTray()
        case .error: ErrorTray()
        case .success: SuccessTray()
        case .form: FormTray()
        case .list: ListTray()
        case .depositFlow: DepositFlowTray()
        case .amount: AmountTray()
        case .amountFlow: AmountFlowTray()
        }
    }
}

/// An X, an SF Symbol and one action.
private struct InfoTray: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Tray(
            title: "End-to-End Encrypted",
            message: "Messages and media in this chat are end-to-end encrypted. Only you and the person you\u{2019}re chatting with can read them.",
            icon: .central(.lock),
            actions: [TrayAction("Got It") { dismiss() }]
        )
    }
}

/// No X and no drag to dismiss: one of two answers.
private struct DecisionTray: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Tray(
            title: "Share Analytics",
            message: "Help us make Flipcash better by sharing anonymous usage data. You can change this anytime in Settings.",
            icon: .central(.circleInfo),
            actions: [
                TrayAction("Don't Share", role: .secondary) { dismiss() },
                TrayAction("Share") { dismiss() },
            ]
        )
    }
}

/// The outcome in a red capsule beside Cancel.
private struct DestructiveTray: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Tray(
            title: "Are You Sure You Want To Log Out?",
            message: "You\u{2019}ll need your Access Key to log back in.",
            icon: .destructive,
            style: .error,
            actions: [
                TrayAction("Cancel", role: .secondary) { dismiss() },
                TrayAction("Log Out", role: .destructive) { dismiss() },
            ]
        )
    }
}

/// The error style with a single action.
private struct ErrorTray: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Tray(
            title: "Something Went Wrong",
            message: "Please try again later.",
            icon: .destructive,
            style: .error,
            actions: [TrayAction("OK") { dismiss() }]
        )
    }
}

/// The success style, presented not dismissable as `DialogItem.success` is.
private struct SuccessTray: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Tray(
            title: "Report Sent",
            message: "Thanks. We\u{2019}ll take a look.",
            icon: .central(.circleCheck),
            style: .success,
            actions: [TrayAction("OK") { dismiss() }]
        )
    }
}

/// No icon; a text field over the keyboard, and the CTA through disabled, loading and success.
private struct FormTray: View {

    @State private var name = ""
    @State private var state: ButtonState = .normal
    @FocusState private var isFocused: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Tray(
            title: "What\u{2019}s Your Name?",
            message: "This is how you\u{2019}ll appear to others.",
            actions: [
                TrayAction("Save", state: state, isEnabled: !name.isEmpty) { save() },
            ]
        ) {
            InputContainer(highlighted: isFocused) {
                TextField("Your Name", text: $name)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, 15)
            }
        }
        .onAppear { isFocused = true }
    }

    private func save() {
        Task {
            state = .loading
            try? await Task.sleep(for: .seconds(1))
            state = .success
            try? await Task.sleep(for: .milliseconds(500))
            dismiss()
        }
    }
}

/// Selectable rows as custom content, under two actions.
private struct ListTray: View {

    private let options = ["1 Hour", "8 Hours", "1 Week", "Always"]

    @State private var selection = "8 Hours"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Tray(
            title: "Mute Notifications",
            message: "You\u{2019}ll still receive messages and see unread counts.",
            icon: .central(.bellOff),
            actions: [
                TrayAction("Cancel", role: .secondary) { dismiss() },
                TrayAction("Mute") { dismiss() },
            ]
        ) {
            VStack(spacing: TrayOptionRow.gap) {
                ForEach(options, id: \.self) { option in
                    TrayOptionRow(option, icon: .clock, isSelected: option == selection) {
                        selection = option
                    }
                }
            }
        }
    }
}

/// Three steps at three heights behind an asset icon: education, address, confirm. Exercises the
/// X as back and the CTA's title changing in place.
private struct DepositFlowTray: View {

    enum Step: Hashable {
        case education
        case address
        case confirm
    }

    @State private var flow = TrayFlow(root: Step.education)
    /// Which way a tuner replay walks the flow; it turns at either end.
    @State private var replaysForward = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TrayStack(flow: flow, icon: .image(.asset(.buyUSDC)), actions: actions) { step in
            switch step {
            case .education:
                TrayPage(
                    title: "Manually Deposit USDC",
                    message: "This will not purchase the amount you selected. Once your USDC is deposited, you can buy."
                )
            case .address:
                TrayPage(
                    title: "Your Deposit Address",
                    message: "Send only USDC on Solana to this address."
                ) {
                    ImmutableField("7Hf3kQ2nWzR8vLpA9cXtE5uJ1mYbD4sGqN6oKiV2TjPw")
                }
            case .confirm:
                TrayPage(title: "Confirm Deposit", message: "We'll let you know when it arrives.")
            }
        }
        // A motion release walks the flow forward to the end, then back.
        .onTunerReplay("Tray Motion") { replayStep() } // LOCAL-TUNER
        .onTunerReplay("Tray Label") { replayStep() } // LOCAL-TUNER
        .task {
            guard TraySandbox.autoplays else { return }
            for _ in 0..<4 {
                try? await Task.sleep(for: .seconds(1.5))
                replayStep()
            }
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }

    private func actions(for step: Step) -> [TrayAction] {
        switch step {
        case .education: [TrayAction("Next") { flow.push(.address) }]
        case .address: [TrayAction("Continue") { flow.push(.confirm) }]
        case .confirm: [TrayAction("Confirm") { dismiss() }]
        }
    }

    private func replayStep() {
        if replaysForward {
            switch flow.current {
            case .education: flow.push(.address)
            case .address: flow.push(.confirm)
            case .confirm:
                replaysForward = false
                flow.back()
            }
        } else {
            flow.back()
            if !flow.canGoBack { replaysForward = true }
        }
    }
}

// MARK: - Amount

/// The sandbox's balance, matching the backdrop's "$1,250.00 available".
private let sandboxBalance: Decimal = 1250

/// The parsed amount for `string`, through the one parser keypad amounts use.
private func sandboxAmount(_ string: String) -> Decimal? {
    AmountValidator().validate(string)
}

/// `amount` formatted for display; whole amounts drop their cents unless `showsCents`.
private func sandboxFormatted(_ amount: Decimal, showsCents: Bool = false) -> String {
    NumberFormatter.fiat(currency: .usd, minimumFractionDigits: showsCents ? 2 : 0).string(from: amount as NSDecimalNumber) ?? ""
}


/// Whether `string` is an amount the CTA can go on with.
private func sandboxCanContinue(_ string: String) -> Bool {
    guard let amount = sandboxAmount(string) else { return false }
    return amount > 0 && amount <= sandboxBalance
}

/// The keypad page, captioned with the balance, in the error colour once the amount passes it.
private struct SandboxAmountPage: View {

    @Binding var amount: String

    var body: some View {
        let exceeds = (sandboxAmount(amount) ?? 0) > sandboxBalance
        TrayPage {
            TrayAmountEntry(
                amount: $amount,
                currency: .usd,
                caption: "\(sandboxFormatted(sandboxBalance, showsCents: true)) available",
                isCaptionError: exceeds
            )
        }
    }
}

/// One step: the keypad, its title in the header beside the X.
private struct AmountTray: View {

    private enum Step: Hashable {
        case only
    }

    @State private var flow = TrayFlow(root: Step.only)
    @State private var amount = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TrayStack(
            flow: flow,
            icon: { _ in nil },
            headerTitle: { _ in "Add Cash" },
            actions: { _ in [TrayAction("Continue", isEnabled: sandboxCanContinue(amount)) { dismiss() }] }
        ) { _ in
            SandboxAmountPage(amount: $amount)
        }
    }
}

/// Presets in a grid, then a custom amount on the keypad, then a review: three heights in one
/// tray, every title in the header so only the line itself crossfades between steps, and Continue
/// holding its place until the last step.
private struct AmountFlowTray: View {

    enum Step: Hashable {
        case choose
        case custom
        case review
    }

    private static let presets = ["10", "25", "50", "100", "250"]

    @State private var flow = TrayFlow(root: Step.choose)
    @State private var preset: String?
    @State private var custom = ""
    /// Whether the review shows the custom amount rather than a preset.
    @State private var usesCustom = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TrayStack(flow: flow, icon: { _ in nil }, headerTitle: headerTitle, actions: actions) { step in
            switch step {
            case .choose:
                TrayPage(message: "Choose how much to add to your balance.") {
                    LazyVGrid(columns: TrayOptionTile.columns, spacing: TrayMetrics.rowGap) {
                        ForEach(Self.presets, id: \.self) { value in
                            TrayOptionTile(sandboxFormatted(Decimal(string: value) ?? 0), isSelected: preset == value) {
                                preset = value
                            }
                        }
                        TrayOptionTile("Custom") {
                            flow.push(.custom)
                        }
                    }
                }
            case .custom:
                SandboxAmountPage(amount: $custom)
            case .review:
                // The amount where the keypad step drew it, so the step reads as the same number settling.
                TrayPage {
                    VStack(alignment: .leading, spacing: TrayAmountMetrics.amountToCaption) {
                        Text(verbatim: sandboxFormatted(reviewAmount))
                            .font(.default(size: TrayAmountMetrics.amountSize, weight: .bold))
                            .foregroundStyle(Color.textMain)
                            .frame(height: TrayAmountMetrics.amountHeight)
                        Text("It\u{2019}ll be in your balance right away. You can withdraw it at any time.")
                            .font(.default(size: TrayAmountMetrics.captionSize))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var reviewAmount: Decimal {
        sandboxAmount(usesCustom ? custom : preset ?? "") ?? 0
    }

    private func headerTitle(for step: Step) -> String? {
        switch step {
        case .choose: "Choose Amount"
        case .custom: "Custom Amount"
        case .review: "Review"
        }
    }

    private func actions(for step: Step) -> [TrayAction] {
        switch step {
        case .choose:
            [TrayAction("Continue", isEnabled: preset != nil) {
                usesCustom = false
                flow.push(.review)
            }]
        case .custom:
            [TrayAction("Continue", isEnabled: sandboxCanContinue(custom)) {
                usesCustom = true
                flow.push(.review)
            }]
        case .review:
            [TrayAction("Add Cash") { dismiss() }]
        }
    }
}

// MARK: - Cross check

/// `CrossMediumShape` and the Central `crossMedium` asset at the tray X's tuned size, apart and
/// overlaid (shape red, asset green, yellow where both draw), and the overlay at 10×
/// (`--tray-sandbox-cross`).
private struct CrossComparison: View {

    var body: some View {
        let box = TrayMetrics.closeGlyphSize / CrossMediumShape.extentRatio
        VStack(spacing: 60) {
            HStack(spacing: 24) {
                shape.frame(width: box, height: box)
                asset.frame(width: box, height: box)
                overlay.frame(width: box, height: box)
            }
            overlay
                .frame(width: box, height: box)
                .scaleEffect(10)
                .frame(width: box * 10, height: box * 10)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var overlay: some View {
        ZStack {
            shape.foregroundStyle(.red)
            asset.foregroundStyle(.green).blendMode(.screen)
        }
    }

    private var shape: some View {
        CrossMediumShape()
            .stroke(style: StrokeStyle(lineWidth: TrayMetrics.closeStroke, lineCap: .round))
    }

    private var asset: some View {
        Image.icon(.crossMedium).resizable()
    }
}

// MARK: - Backdrop

/// A static Amount Entry look-alike for the trays to float over, built from plain text.
private struct AmountEntryBackdrop: View {

    let lastDismissed: String?
    let open: (TrayKind) -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("$24.50")
                    .font(.appDisplayLarge)
                    .foregroundStyle(Color.textMain)
                Text(lastDismissed.map { "\($0) dismissed" } ?? "$1,250.00 available")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 24) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.appKeyboard)
                        .foregroundStyle(Color.textMain.opacity(0.35))
                }
            }
            .padding(.bottom, 32)
            .accessibilityHidden(true)

            // Below the keypad, where the tuner panel never docks.
            Menu {
                ForEach(TrayKind.allCases) { kind in
                    Button(kind.name) { open(kind) }
                }
            } label: {
                Text("Open a Tray")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.filled20Compact)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundMain)
    }
}

// MARK: - Previews

/// A tray's card over the app background, as it sits at the bottom of the screen.
private struct TrayPreviewCard: View {

    let kind: TrayKind

    var body: some View {
        kind.tray
            .environment(\.trayIsDismissable, kind.isDismissable)
            .padding(8)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .background(Color.backgroundMain)
            .preferredColorScheme(.dark)
    }
}

#Preview("Info") { TrayPreviewCard(kind: .info) }
#Preview("Decision") { TrayPreviewCard(kind: .decision) }
#Preview("Destructive") { TrayPreviewCard(kind: .destructive) }
#Preview("Error") { TrayPreviewCard(kind: .error) }
#Preview("Success") { TrayPreviewCard(kind: .success) }
#Preview("Text field") { TrayPreviewCard(kind: .form) }
#Preview("List") { TrayPreviewCard(kind: .list) }
#Preview("Multi-step flow") { TrayPreviewCard(kind: .depositFlow) }

#Preview("Flow, second step") {
    let flow = TrayFlow(root: 0)
    flow.push(1)
    return TrayStack(flow: flow, icon: .image(.asset(.buyUSDC)), actions: { _ in [TrayAction("Confirm") {}] }) { _ in
        TrayPage(title: "Confirm Deposit", message: "We'll let you know when it arrives.")
    }
    .padding(8)
    .frame(maxHeight: .infinity, alignment: .bottom)
    .background(Color.backgroundMain)
}

#Preview("CTA states") {
    VStack(spacing: 12) {
        TrayActionBar(actions: [TrayAction("Disabled", isEnabled: false) {}])
        TrayActionBar(actions: [TrayAction("Loading", state: .loading) {}])
        TrayActionBar(actions: [TrayAction("Done", state: .success) {}])
    }
    .padding(24)
    .frame(maxHeight: .infinity)
    .background(Color.backgroundMain)
}

#Preview("Largest Dynamic Type") {
    TrayPreviewCard(kind: .destructive)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Tray sandbox") {
    TraySandbox()
}
#endif
