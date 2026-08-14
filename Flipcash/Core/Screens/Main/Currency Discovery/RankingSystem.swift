//
//  RankingSystem.swift
//  Flipcash
//

import Foundation

/// The metric the discovery leaderboard ranks by, which also drives what each
/// row's prominent value and weekly delta represent.
///
/// Market-cap ranking is the intended direction for the new UI, but the Discover
/// API only returns a *holder* weekly delta (`HolderMetrics.holderDeltas`) and a
/// point-in-time market cap — there is no market-cap delta yet. Until that lands
/// we rank by holders in both UIs.
enum RankingSystem {
    /// Rank by holder count; the weekly delta is the change in holders.
    case holders
    /// Rank by market capitalization; the weekly delta is the change in market cap.
    case marketCap
}
