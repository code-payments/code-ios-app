//
//  EnterAmountView.swift
//  Code
//
//  Created by Dima Bart on 2021-04-05.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

public struct EnterAmountView: View {
    
    @Environment(Session.self) var session
    @Environment(RatesController.self) var rateController
    
    @Binding public var enteredAmount: String
    @Binding public var actionState: ButtonState
    
    private let mode: Mode
    private let subtitle: Subtitle
    private let actionEnabled: (String) -> Bool
    private let action: () -> Void
    private let actionOverride: AnyView?
    private let actionTitle: String?
    /// Optional control shown just above the keypad — the Convert flow's
    /// "Convert to [currency]" destination selector lives here.
    private let accessory: AnyView?
    /// Optional replacement for the default centered amount + subtitle block.
    /// The left-aligned flows pass an `EnterAmountHeader`; when set, the amount
    /// sits at the top rather than centered in the upper area.
    private let header: AnyView?

    /// The hosted swipe's travel, which dims the rest of the screen.
    @State private var swipeProgress: CGFloat = 0

    // MARK: - Calculator -
    
    private var calculator: EnterAmountCalculator {
        EnterAmountCalculator(
            mode: mode,
            selectedCurrency: rateController.balanceCurrency,
            sendLimitProvider: session.sendLimitFor(currency:)
        )
    }
    
    // MARK: - Init -
    
    init(
        mode: Mode,
        enteredAmount: Binding<String>,
        subtitle: Subtitle,
        actionState: Binding<ButtonState>,
        actionEnabled: @escaping (String) -> Bool,
        action: @escaping () -> Void,
        actionTitle: String? = nil,
        accessory: AnyView? = nil,
        header: AnyView? = nil
    ) {
        self.mode                    = mode
        self.subtitle                = subtitle
        self._enteredAmount          = enteredAmount
        self._actionState            = actionState
        self.actionEnabled           = actionEnabled
        self.action                  = action
        self.actionOverride          = nil
        self.actionTitle             = actionTitle
        self.accessory               = accessory
        self.header                  = header
    }

    /// Variant where the caller supplies the bottom action control (e.g.
    /// `SwipeControl`) instead of the default `CodeButton`. The control inherits
    /// the same disabled gating via `actionEnabled`.
    init<ActionContent: View>(
        mode: Mode,
        enteredAmount: Binding<String>,
        subtitle: Subtitle,
        actionEnabled: @escaping (String) -> Bool,
        header: AnyView? = nil,
        @ViewBuilder actionContent: () -> ActionContent
    ) {
        self.mode                    = mode
        self.subtitle                = subtitle
        self._enteredAmount          = enteredAmount
        self._actionState            = .constant(.normal)
        self.actionEnabled           = actionEnabled
        self.action                  = {}
        self.actionOverride          = AnyView(actionContent())
        self.actionTitle             = nil
        self.accessory               = nil
        self.header                  = header
    }
    
    // MARK: - Computed -

    private var isExceedingLimit: Bool {
        guard let value = AmountValidator().validate(enteredAmount), value > 0 else {
            return false
        }
        return !actionEnabled(enteredAmount)
    }

    /// The action takes taps only while it isn't already running or showing its result.
    private var isActionIdle: Bool {
        if case .normal = actionState { return true }
        return false
    }

    private var subtitleColor: Color {
        isExceedingLimit ? .textError : .textSecondary
    }

    /// The opacity everything but the swipe takes at the hosted swipe's current travel.
    private var dimOpacity: Double {
        guard actionOverride != nil else { return 1 }
        let travel = min(max(Double(swipeProgress), 0), 1)
        return 1 - (1 - SwipeDim.maxDim) * travel
    }

    /// An error subtitle stays bright while the rest dims.
    private var subtitleOpacity: Double {
        switch subtitle {
        case .error: 1
        case .singleTransactionLimit, .balanceWithLimit, .hidden: dimOpacity
        }
    }

    // MARK: - Body -

    public var body: some View {
        VStack(alignment: header == nil ? .center : .leading) {
            if let header {
                // A gap below the nav bar so the amount isn't jammed against the
                // chrome; capped at 24 but allowed to shrink on small screens so
                // the keypad never gets pushed off. The flexible spacer below
                // absorbs the rest on taller devices.
                Spacer().frame(maxHeight: 24)
                header
            } else {
                Spacer()

                VStack(spacing: 5) {
                    HStack(spacing: 15) {
                        AmountField(
                            content: $enteredAmount,
                            defaultValue: mode.defaultValue,
                            prefix: .none,
                            formatter: mode.formatter(with: calculator.currency),
                            suffix: nil
                        )
                        .foregroundStyle(.textMain)
                    }

                    Group {
                        switch subtitle {
                        case .singleTransactionLimit:
                            if let limit = calculator.maxTransactionAmount {
                                Text("Enter up to \(limit.formatted())")
                                    .fixedSize()
                                    .foregroundStyle(subtitleColor)
                                    .font(.appTextMedium)
                            }

                        case .balanceWithLimit(let maxBalance):
                            Text("Enter up to \(calculator.maxEnterAmount(maxBalance: maxBalance).formatted())")
                                .fixedSize()
                                .foregroundStyle(subtitleColor)
                                .font(.appTextMedium)

                        case .error(let text):
                            Text(text)
                                .fixedSize()
                                .foregroundStyle(.textError)
                                .font(.appTextMedium)

                        case .hidden:
                            EmptyView()
                        }
                    }
                    .opacity(subtitleOpacity)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()

            if let accessory {
                accessory
                    .opacity(dimOpacity)
                // Capped but shrinkable so the keypad/button aren't pushed off
                // on small (SE-class) screens.
                Spacer()
                    .frame(maxHeight: 20)
            }

            KeyPadView(
                content: $enteredAmount,
                configuration: calculator.currency.maximumFractionDigits > 0 ? .decimal() : .number(),
                rules: KeyPadView.CurrencyRules(
                    maxIntegerDigits: 9,
                    maxDecimalDigits: calculator.currency.maximumFractionDigits
                )
            )
            .padding([.leading, .trailing], -20)
            .opacity(dimOpacity)
            // The amount can't change mid-send, so the keypad locks whenever the thumb is off rest.
            .allowsHitTesting(swipeProgress == 0)

            if let actionOverride {
                actionOverride
                    .disabled(!actionEnabled(enteredAmount))
                    // Sits in the Next button's slot: same side and bottom insets as the button below.
                    .padding(.top, SwipeDim.keypadToSwipe)
                    .modifier(ActionSlotInsets())
            } else {
                Button(action: action) {
                    ButtonStateLabel(actionTitle ?? mode.actionName, state: actionState)
                }
                .buttonStyle(AmountActionButtonStyle())
                .disabled(!actionEnabled(enteredAmount) || !isActionIdle)
                // Amount entry v2: 32 from the screen's sides and bottom (the screens already pad 20),
                // 20 below the keypad.
                .padding(.top, 20)
                .modifier(ActionSlotInsets())
            }
        }
        // The control animates the value on its own snap-back and sends every frame, so it lands unanimated.
        .onPreferenceChange(SwipeControlProgressKey.self) { progress in
            withTransaction(Transaction(animation: nil)) { swipeProgress = progress }
        }
    }
}

// MARK: - Swipe dim -

/// How the amount screen lays out and dims around a hosted swipe; the entered amount never dims.
private enum SwipeDim {
    /// The opacity everything but the amount and the swipe falls to at full travel.
    static let maxDim: Double = 0.1
    /// The gap between the keypad and the hosted swipe.
    static let keypadToSwipe: CGFloat = 20
}

/// The side and bottom insets of the action slot, shared by the Next button and a hosted swipe so
/// the two can't drift.
private struct ActionSlotInsets: ViewModifier {
    func body(content: Content) -> some View {
        // 32 from the screen's bottom edge on any device: the screens pad 20 inside the safe area,
        // so the slot reads the inset from the window, never touching it in its own geometry.
        let bottomInset = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        content
            .padding(.horizontal, 32 - 20)
            .padding(.bottom, 32 - 20 - bottomInset)
    }
}

// MARK: - Mode -

extension EnterAmountView {
    enum Mode {

        case currency
        case withdraw
        case buy
        case sell
        case convert
        case addMoney
        /// Setting the minimum tip another user must pay to DM you. Not a
        /// transaction, so no send limit applies.
        case minimumTip
        /// Setting the balance a member has to hold to get into a group. Not a
        /// transaction either — nothing moves — so no send limit applies.
        case balanceRequirement

        fileprivate func formatter(with currency: CurrencyCode) -> NumberFormatter {
            switch self {
            case .currency, .withdraw, .buy, .sell, .convert, .addMoney, .minimumTip, .balanceRequirement:
                return .fiat(currency: currency, minimumFractionDigits: 0)
            }
        }

        fileprivate var defaultValue: AmountField.DefaultValue {
            switch self {
            case .currency, .withdraw, .buy, .sell, .convert, .addMoney, .minimumTip, .balanceRequirement: return .number("0")
            }
        }

        fileprivate var actionName: String {
            switch self {
            case .currency: return "Next"
            case .withdraw: return "Next"
            case .buy:      return "Buy"
            case .sell:     return "Next"
            case .convert:  return "Next"
            case .addMoney: return "Add Money"
            case .minimumTip: return "Save"
            case .balanceRequirement: return "Done"
            }
        }

        fileprivate var buttonStyle: CodeButton.Style {
            switch self {
            case .currency, .withdraw, .buy, .sell, .convert, .addMoney, .minimumTip, .balanceRequirement: return .filled
            }
        }
    }
}

// MARK: - Subtitle -

extension EnterAmountView {
    enum Subtitle {
        case singleTransactionLimit
        case balanceWithLimit(ExchangedFiat)
        /// Always rendered in `textError`. Use for soft-validation copy where
        /// Next stays enabled and the caller surfaces a dialog on tap.
        case error(String)
        /// Nothing under the amount — for screens that pass a `header`, which
        /// replaces this block outright.
        case hidden
    }
}

// MARK: - Previews -

#Preview {
    EnterAmountView(
        mode: .currency,
        enteredAmount: .constant("123"),
        subtitle: .singleTransactionLimit,
        actionState: .constant(.normal),
        actionEnabled: { _ in return true }
    ) {}
}


// MARK: - Action button -

/// The amount screen's primary action: a full-width capsule in the action colour, faded when disabled.
private struct AmountActionButtonStyle: ButtonStyle {

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .foregroundStyle(isEnabled ? Color.textAction : Color.textMain.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(isEnabled ? Color.action : Color.action.opacity(0.1))
            }
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
