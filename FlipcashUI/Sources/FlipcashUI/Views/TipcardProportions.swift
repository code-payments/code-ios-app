//
//  TipcardProportions.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreGraphics

/// The tip card's proportions, shared by the tip card and by every card drawn in its likeness.
///
/// Everything is a fraction of the card's width, so a card drawn at any width keeps the tip card's
/// shape and type scale.
public enum TipcardProportions {

    /// The card's height-to-width proportion. From Figma's 269 x 333 card, which holds that
    /// proportion both on the You page (node 9276:4641) and full screen (node 9277:121417).
    public static let aspectRatio: CGFloat = 333.0 / 269.0

    /// The name's size as a fraction of the card's width. Figma draws the name at 17 on the
    /// 269-wide card and scales it with the card, so the 302-wide full-screen card gets 19.1
    /// (node 9277:121421) and the 242-wide You-page card 15.3 (node 9276:4645). A fixed size instead
    /// left the name looking oversized on the small card and undersized on the big one.
    public static let nameFraction: CGFloat = 17.0 / 269.0

    /// The gap between the name and the subtitle, as a fraction of the card's width so it scales
    /// with the type. From node 9443:7991's 4 on the 241.6-wide card.
    public static let subtitleGapFraction: CGFloat = 4.0 / 241.636

    /// The corner radius as a fraction of the card's width.
    public static let cornerRadiusFraction: CGFloat = 0.08

    /// The subtitle's opacity under the name. Medium weight at half opacity is what separates the
    /// handle from the name, at the name's own size (node 9443:7991).
    public static let subtitleOpacity: Double = 0.5
}
