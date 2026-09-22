//
//  ReportFlowScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Reporting a person, a group, or a message.
///
/// Two steps, and most reports only see the first: picking a reason and confirming it files the
/// report. ``ReportReason/other`` is the exception, because only it has nothing to go on without a
/// second screen.
///
/// Steps rather than one sheet that swaps its own contents. A sheet sized to its content is the
/// wrong shape for a step that grows a text field and a keyboard, and the choice also buys a real
/// back: returning to the reasons keeps both the pick and the words, because leaving the details by
/// the back arrow is usually a second thought about the reason rather than about what happened.
///
/// What goes on the wire is assembled by ``ReportDescription/build(reason:details:)`` in shared
/// code, so this screen and Android's produce the same `description` for the same choice. Nothing
/// here formats anything.
struct ReportFlowScreen: View {

    let target: ReportTarget

    @State private var state = ReportFlowState()
    @State private var dialog: DialogItem?
    @State private var direction: Direction = .forward

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionContainer.self) private var sessionContainer

    private enum Direction {
        case forward, backward

        var slide: AnyTransition {
            switch self {
            case .forward:
                .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
            case .backward:
                .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
            }
        }
    }

    var body: some View {
        Background(color: .backgroundMain) {
            ZStack {
                switch state.step {
                case .reason:
                    ReasonStep(state: state, onContinue: advance)
                        .transition(direction.slide)
                case .details:
                    DetailsStep(state: state, onSubmit: submitDetails)
                        .transition(direction.slide)
                }
            }
        }
        .navigationTitle("Report")
        .toolbarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // A half-written report is not something to lose to a stray downward drag.
        .interactiveDismissDisabled()
        .toolbar {
            // One control per step, in the corner iOS puts it: dismissal trailing, back leading.
            // Past the reasons the only way out is back through them, so the details a person has
            // typed cannot be dropped by a control sitting next to the keyboard.
            switch state.step {
            case .reason:
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                        .accessibilityIdentifier("report-nav-close")
                }

            case .details:
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: goBackToReasons) {
                        Image(systemName: "chevron.backward")
                            .foregroundStyle(Color.textMain)
                    }
                    .accessibilityIdentifier("report-nav-back")
                    .accessibilityLabel("Back")
                }
            }
        }
        .dialog(item: $dialog)
    }

    private func goBackToReasons() {
        direction = .backward
        withAnimation { state.step = .reason }
    }

    /// The button at the bottom of the reasons: a second, deliberate press on a pick already made.
    ///
    /// Tapping a row only selects it. Filing a report cannot be undone from here and the labels sit
    /// close enough together that a mis-tap is a plausible way to reach the wrong one, so the extra
    /// press buys back a whole class of mistake for one tap.
    private func advance() {
        guard let reason = state.selectedReason else { return }
        if ReportFlowState.needsDetails(reason) {
            direction = .forward
            withAnimation { state.step = .details }
        } else {
            Task { await submit(reason, details: nil) }
        }
    }

    private func submitDetails() {
        guard let reason = state.selectedReason else { return }
        Task { await submit(reason, details: state.details) }
    }

    /// Files the report, then waits to be acknowledged.
    ///
    /// What closes this flow is the confirmation being dismissed, not the send returning. A report
    /// answers inside a frame, so a flow that vanished on the call would leave its confirmation to
    /// land on whatever happened to be behind it — and say nothing at all when the send had failed.
    ///
    /// The contract makes a duplicate report a no-op that answers OK, so the acknowledgement reads
    /// the same whether or not this was the first one. Telling someone they had already reported
    /// this would be answering a question they did not ask.
    private func submit(_ reason: ReportReason, details: String?) async {
        state.buttonState = .loading

        // A floor under the spinner, run alongside the send rather than before it: the call
        // answers inside a frame, so without one the spinner never renders, and with a blocking
        // delay a slow send would be held back by its own progress indicator.
        let floor = Task { try? await Task.sleep(for: .milliseconds(400)) }

        do {
            try await sessionContainer.flipClient.report(
                owner: sessionContainer.session.ownerKeyPair,
                target: target,
                description: ReportDescription.build(reason: reason, details: details)
            )
            await floor.value
            state.buttonState = .success
            // The checkmark is drawn on the frame after the state flips, so raising the dialog
            // immediately would drop a scrim over one nobody saw.
            try? await Task.sleep(for: .milliseconds(500))
            dialog = DialogItem.success(
                title: "Report Sent",
                subtitle: "Thanks. We'll take a look"
            ).onDismiss { dismiss() }
        } catch {
            floor.cancel()
            // Left where it was, with the reason still picked: a retry is one press.
            state.buttonState = .normal
            dialog = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to send your report. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to file report")
        }
    }
}

// MARK: - ReasonStep

private struct ReasonStep: View {

    @Bindable var state: ReportFlowState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text("Tell us what's wrong. Your report is private — we won't tell them who reported")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)

                    VStack(spacing: 8) {
                        ForEach(ReportReason.displayOrder, id: \.self) { reason in
                            ReportReasonRow(
                                reason: reason,
                                isSelected: state.selectedReason == reason
                            ) {
                                state.selectedReason = reason
                            }
                        }
                    }
                    .padding(.top, 24)
                }
            }
            .scrollIndicators(.hidden)

            CodeButton(
                state: state.buttonState,
                style: .filled,
                title: ReportFlowState.buttonTitle(for: state.selectedReason),
                disabled: state.selectedReason == nil || state.buttonState != .normal,
                action: onContinue
            )
            .accessibilityIdentifier("report-reason-continue")
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - ReportReasonRow

/// One choice: an indicator, its label, and the line of scope under it.
///
/// The whole row is the target and the indicator only reports state, so there is no second,
/// smaller thing to hit inside it.
private struct ReportReasonRow: View {

    let reason: ReportReason
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.textMain : Color.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(reason.title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)

                    Text(reason.summary)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundRow, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("report-reason-\(reason.identifier)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - DetailsStep

private struct DetailsStep: View {

    @Bindable var state: ReportFlowState
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    /// Counts down rather than up, matching the currency wizard's fields.
    private var remaining: Int {
        ReportDescription.maxDetailsLength - state.details.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Two blocks rather than one sentence: the ask is what the screen wants, the
                    // privacy line is what it offers in return. Run together at one weight they
                    // compete, and the part that reassures is the part that gets skipped.
                    Text("Tell us what's wrong")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Your report is private — we won't tell them who reported")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Tell us more", text: $state.details, axis: .vertical)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .focused($isFocused)
                        .padding(.top, 16)
                        .accessibilityIdentifier("report-details")
                        .onChange(of: state.details) { _, new in
                            // Clipped rather than refused: the cap is the contract's, not a rule
                            // anyone broke, and the counter above has been saying so all along.
                            if new.count > ReportDescription.maxDetailsLength {
                                state.details = String(new.prefix(ReportDescription.maxDetailsLength))
                            }
                        }

                    Color.clear.frame(height: 60)
                }
                .padding(.top, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            Text("\(remaining) characters")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("report-details-counter")
                .padding(.bottom, 12)

            // Picking "Something Else" and then saying nothing leaves the report with less to go
            // on than any other row would have carried, so the button waits.
            CodeButton(
                state: state.buttonState,
                style: .filled,
                title: "Submit Report",
                disabled: !ReportFlowState.canSubmitDetails(state.details) || state.buttonState != .normal,
                action: onSubmit
            )
            .accessibilityIdentifier("report-submit")
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .onAppear { isFocused = true }
    }
}
