//
//  RankingSystem.swift
//  Flipcash
//

import Foundation

/// The metric the discovery leaderboard ranks by, which also drives what each
/// row's prominent value and weekly delta represent.
///
/// The leaderboard ranks by market cap: the Discover RPC returns
/// `MarketCapMetrics` (`current_market_cap` + per-range deltas), so a row shows
/// the current market cap and its weekly change. Holder metrics remain
/// available as the secondary line and an alternate ranking.
enum RankingSystem {
    /// Rank by holder count; the weekly delta is the change in holders.
    case holders
    /// Rank by market capitalization; the weekly delta is the change in market cap.
    case marketCap
}
