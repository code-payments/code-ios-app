//
//  AttachPanelTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Attach panel")
struct AttachPanelTests {

    @Test("A fresh panel is closed and asks the bar for no room above it")
    func freshPanelIsClosed() {
        let panel = AttachPanel()
        #expect(!panel.isOpen)
        #expect(!panel.holdsOverflow)
    }

    @Test("Tapping + opens the panel and a second tap collapses it back")
    func toggleOpensAndCollapses() {
        let panel = AttachPanel()
        panel.toggle()
        #expect(panel.isOpen)
        #expect(panel.holdsOverflow)

        panel.toggle()
        #expect(!panel.isOpen)
    }

    @Test("Dismissing keeps the room above the bar until the collapse has finished")
    func overflowOutlivesTheCollapse() {
        let panel = AttachPanel()
        panel.open()
        panel.dismiss()
        #expect(!panel.isOpen)
        #expect(panel.holdsOverflow)

        panel.exitDidFinish()
        #expect(!panel.holdsOverflow)
    }

    @Test("A collapse that finishes after the panel reopened keeps the room")
    func staleExitLeavesOpenPanelAlone() {
        let panel = AttachPanel()
        panel.open()
        panel.dismiss()
        panel.open()

        panel.exitDidFinish()
        #expect(panel.isOpen)
        #expect(panel.holdsOverflow)
    }

    @Test("Dismissing a closed panel changes nothing")
    func dismissWhenClosedIsNoOp() {
        let panel = AttachPanel()
        panel.dismiss()
        #expect(!panel.isOpen)
        #expect(!panel.holdsOverflow)
    }

    @Test("Back from a card takes it down and puts the panel back up, in one change")
    func barReturnsToMenu() {
        let model = ConversationBarModel()
        model.attachCard.open(.photos, screenHeight: 874)

        model.returnToMenu()
        #expect(!model.attachCard.isOpen)
        #expect(model.attachPanel.isOpen)
        #expect(model.attachPanel.holdsOverflow)
        #expect(model.attachSurfacePhase == .menu)
    }

    @Test("Back with no card up leaves the panel down")
    func returnToMenuWithoutCardIsNoOp() {
        let model = ConversationBarModel()
        model.returnToMenu()
        #expect(!model.attachPanel.isOpen)
    }

    @Test("Back from the photo card discards the pick")
    func backResetsPick() {
        let model = ConversationBarModel()
        model.attachCard.open(.photos, screenHeight: 874)
        model.photosPick.showsLibrary = true

        model.returnToMenu()
        #expect(model.photosPick.selection.isEmpty)
        #expect(!model.photosPick.showsLibrary)
    }

    @Test("Adding hands the loader on and starts a fresh one, so its reads are not cancelled")
    func addHandsOffPreloader() {
        let pick = AttachPhotosPick()
        let before = pick.preloader
        var received: AnyObject?
        pick.handOff { _, preloader in received = preloader }
        #expect(received === before)
        #expect(pick.preloader !== before)
        #expect(pick.selection.isEmpty)
    }

    @Test("The bar asks for room above itself everywhere for the panel, and only over the card for a card")
    func barOverflow() {
        let model = ConversationBarModel()
        #expect(model.overflow == .none)

        model.attachPanel.open()
        #expect(model.overflow == .everywhere)
        #expect(model.overflow.touchTop == nil)

        model.attachPanel.dismiss()
        model.attachPanel.exitDidFinish()
        model.attachCard.open(.camera, screenHeight: 874)
        model.cardTop = 300
        #expect(model.overflow == .band(top: 300))

        // Leaving, the card takes no touches; once it has gone, the bar stops overflowing.
        model.attachCard.close()
        #expect(model.overflow.overflows)
        #expect(model.overflow.touchTop == .greatestFiniteMagnitude)
        model.attachCard.exitDidFinish()
        #expect(model.overflow == .none)
    }

    @Test("Over the keyboard the bar claims no room, even with the panel up: the overlay takes its touches")
    func overKeyboardClaimsNoRoom() {
        let model = ConversationBarModel()
        model.overKeyboard.activate(items: [.camera, .photos])
        model.attachPanel.open()
        #expect(model.overflow == .none)
    }
}

@MainActor
@Suite("Attach surface")
struct AttachSurfaceTests {

    @Test("The surface shows the menu, then the card in its place, then the landing, then nothing")
    func phases() {
        let model = ConversationBarModel()
        #expect(model.attachSurfacePhase == .collapsed)
        #expect(!model.attachSurfaceIsMounted)

        model.attachPanel.open()
        #expect(model.attachSurfacePhase == .menu)
        #expect(model.attachSurfaceIsMounted)

        // One transaction in the app: the panel closes as the card opens, and the card wins.
        model.attachPanel.dismiss()
        model.attachCard.open(.camera, screenHeight: 874)
        #expect(model.attachSurfacePhase == .card(.camera))

        let chip = UUID()
        model.attachCard.beginLanding(on: chip)
        #expect(model.attachSurfacePhase == .card(.camera), "The card stays up until the chip is laid out")
        model.attachCard.close()
        #expect(model.attachSurfacePhase == .landing)

        model.attachPanel.exitDidFinish()
        model.attachCard.exitDidFinish()
        #expect(model.attachSurfaceIsMounted, "The surface stays until it has landed")
        model.attachCard.endLanding()
        #expect(model.attachSurfacePhase == .collapsed)
        #expect(!model.attachSurfaceIsMounted)
    }

    @Test("Only the menu shows rows, and only a card shows card content")
    func contentPerPhase() {
        #expect(AttachSurfacePhase.menu.showsRows)
        #expect(AttachSurfacePhase.menu.shownCard == nil)
        #expect(!AttachSurfacePhase.card(.photos).showsRows)
        #expect(AttachSurfacePhase.card(.photos).shownCard == .photos)
        #expect(!AttachSurfacePhase.collapsed.showsRows && AttachSurfacePhase.collapsed.shownCard == nil)
        #expect(!AttachSurfacePhase.landing.showsRows && AttachSurfacePhase.landing.shownCard == nil)
    }

    @Test("One shape per phase: +, the menu, the card, and the chip, each with its own radius")
    func shapes() {
        let plus = CGRect(x: 16, y: 700, width: 44, height: 44)
        let menu = CGRect(x: 16, y: 600, width: 240, height: 144)
        let card = CGRect(x: 12, y: 300, width: 378, height: 500)
        let chip = CGRect(x: 20, y: 640, width: 56, height: 56)

        let collapsed = AttachSurfaceLayout.shape(for: .collapsed, plus: plus, menu: menu, card: card, landing: chip)
        #expect(collapsed == AttachSurfaceShape(rect: plus, cornerRadius: AttachSurfaceLayout.plusCornerRadius))
        let open = AttachSurfaceLayout.shape(for: .menu, plus: plus, menu: menu, card: card, landing: nil)
        #expect(open == AttachSurfaceShape(rect: menu, cornerRadius: AttachSurfaceLayout.menuCornerRadius))
        let carded = AttachSurfaceLayout.shape(for: .card(.camera), plus: plus, menu: menu, card: card, landing: nil)
        #expect(carded == AttachSurfaceShape(rect: card, cornerRadius: AttachSurfaceLayout.cardCornerRadius))
        let landed = AttachSurfaceLayout.shape(for: .landing, plus: plus, menu: menu, card: card, landing: chip)
        #expect(landed == AttachSurfaceShape(rect: chip, cornerRadius: AttachSurfaceLayout.chipCornerRadius))
        let waiting = AttachSurfaceLayout.shape(for: .landing, plus: plus, menu: menu, card: card, landing: nil)
        #expect(waiting == carded, "Without the chip's frame the surface holds the card's")
    }

    @Test("In the bar the menu stands on +; over the keyboard it straddles the composer's bottom edge")
    func menuPlacement() {
        let plus = CGRect(x: 16, y: 700, width: 44, height: 44)
        let size = CGSize(width: 240, height: 144)
        let standing = AttachSurfaceLayout.menuRect(plus: plus, size: size, placement: .standsOnPlus)
        #expect(standing == CGRect(x: 16, y: 600, width: 240, height: 144))
        let straddling = AttachSurfaceLayout.menuRect(plus: plus, size: size, placement: .straddlesPlus)
        #expect(straddling == AttachOverlayLayout.panelFrame(plusFrame: plus, size: size))
    }

    @Test("The bar's card stands on the row's bottom edge, out to the keyboard-up margin")
    func barCard() {
        let rect = AttachSurfaceLayout.barCardRect(row: CGSize(width: 340, height: 44), outset: 12, height: 500)
        #expect(rect == CGRect(x: -12, y: -456, width: 364, height: 500))
    }

    @Test("Only the menu takes touches while it shows, and only the card while it is up")
    func regions() {
        let menu = CGRect(x: 0, y: 0, width: 10, height: 10)
        let card = CGRect(x: 0, y: 0, width: 20, height: 20)
        #expect(AttachSurfaceLayout.regions(for: .menu, menu: menu, card: card) == [.panel: menu])
        #expect(AttachSurfaceLayout.regions(for: .card(.photos), menu: menu, card: card) == [.card: card])
        #expect(AttachSurfaceLayout.regions(for: .collapsed, menu: menu, card: card).isEmpty)
        #expect(AttachSurfaceLayout.regions(for: .landing, menu: menu, card: card).isEmpty)
    }

    @Test("A landing waits for the chip's frame, then shrinks the card onto it")
    func landingWaitsForChip() {
        let model = ConversationBarModel()
        model.attachCard.open(.photos, screenHeight: 874)
        let chip = UUID()
        model.attachCard.beginLanding(on: chip)

        model.landingChipDidLayout(.zero)
        #expect(model.attachCard.isOpen, "An unlaid-out chip has no frame to land on")
        let frame = CGRect(x: 20, y: 600, width: 56, height: 56)
        model.landingChipDidLayout(frame)
        #expect(!model.attachCard.isOpen)
    }

    @Test("A chip laid out with no landing under way is ignored")
    func landingIgnoresOtherChips() {
        let card = AttachCard()
        #expect(!card.landingChipDidLayout(CGRect(x: 0, y: 0, width: 56, height: 56)))
        #expect(card.landingChipFrame == nil)
    }
}

@Suite("Attach motion")
struct AttachMotionTests {

    @Test("Reduce Motion cross-fades instead of morphing")
    func reduceMotionCrossFades() {
        #expect(AttachMotion(reduceMotion: true) == .crossFade)
        #expect(AttachMotion(reduceMotion: false) == .morph)
    }

    @Test("Only the morph moves the surface; under Reduce Motion it stands still and its content fades")
    func onlyMorphAnimatesGeometry() {
        #expect(AttachMotion.morph.animatesGeometry)
        #expect(!AttachMotion.crossFade.animatesGeometry)
    }

    @Test("The morph grows chips from the chat's tuned scale; the cross-fade holds full size")
    func enterScales() {
        #expect(AttachMotion.morph.chipEnterScale == ChatMotion.composerChipEnterScale)
        #expect(AttachMotion.crossFade.chipEnterScale == 1)
    }

    @Test("The attach flow reuses tuned springs rather than numbers of its own")
    func tokensReuseTunedSprings() {
        #expect(ChatMotion.attachPanel == ChatMotion.swap)
        #expect(ChatMotion.composerChip == ChatMotion.reaction)
    }

    @Test("The card opens and closes without overshoot")
    func attachCardDoesNotOvershoot() {
        #expect(ChatMotion.attachCard == ChatMotion.keyboardScroll)
        #expect(ChatMotion.attachCard.bounce == 0)
    }
}
