import Foundation
import SwiftUI

@MainActor
final class ScoreStore: ObservableObject {
    @Published var matches: [Match] = []
    @Published var details: [String: LiveDetail] = [:]
    @Published var lastUpdated: Date?
    @Published var error: String?
    @Published var watched: Set<String> {
        didSet { UserDefaults.standard.set(Array(watched), forKey: Self.watchedKey) }
    }

    // Cards with the batters & bowlers table open. Remembered across launches.
    @Published var statsOpen: Set<String> {
        didSet { UserDefaults.standard.set(Array(statsOpen), forKey: Self.statsOpenKey) }
    }

    // Team names, as the feed spells them. Their matches show without being picked.
    @Published var favourites: Set<String> {
        didSet { UserDefaults.standard.set(Array(favourites), forKey: Self.favouritesKey) }
    }

    // Favourite-team matches the user chose to stop watching.
    @Published var hidden: Set<String> {
        didSet { UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey) }
    }

    static let watchedKey = "watchedMatchIDs"
    static let statsOpenKey = "statsOpenMatchIDs"
    static let favouritesKey = "favouriteTeams"
    static let hiddenKey = "hiddenMatchIDs"
    let refreshSeconds: UInt64 = 10

    private var loop: Task<Void, Never>?

    init() {
        watched = Set(UserDefaults.standard.stringArray(forKey: Self.watchedKey) ?? [])
        statsOpen = Set(UserDefaults.standard.stringArray(forKey: Self.statsOpenKey) ?? [])
        favourites = Set(UserDefaults.standard.stringArray(forKey: Self.favouritesKey) ?? [])
        hidden = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    // Anything that could put a card on screen: picked matches or favourite teams.
    var followingAnything: Bool { !watched.isEmpty || !favourites.isEmpty }

    var watchedMatches: [Match] {
        matches.filter(isWatched)
    }

    // Picked by hand, or one side is a favourite team. Either way, not if the user hid it.
    func isWatched(_ match: Match) -> Bool {
        !hidden.contains(match.id) && (watched.contains(match.id) || hasFavourite(match))
    }

    func hasFavourite(_ match: Match) -> Bool {
        match.sides.contains { isFavourite($0.name) }
    }

    // Case-insensitive, but otherwise exact: "England" doesn't catch "England Women".
    func isFavourite(_ team: String) -> Bool {
        favourites.contains { $0.caseInsensitiveCompare(team) == .orderedSame }
    }

    func toggleFavourite(_ team: String) {
        if isFavourite(team) {
            favourites = favourites.filter { $0.caseInsensitiveCompare(team) != .orderedSame }
        } else {
            favourites.insert(team)
        }
    }

    func toggle(_ match: Match) {
        if isWatched(match) {
            watched.remove(match.id)
            // A favourite's match would come straight back, so remember it's unwanted.
            if hasFavourite(match) { hidden.insert(match.id) }
        } else {
            hidden.remove(match.id)
            if !hasFavourite(match) { watched.insert(match.id) }
        }
    }

    func toggleStats(_ match: Match) {
        if statsOpen.contains(match.id) { statsOpen.remove(match.id) } else { statsOpen.insert(match.id) }
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: (self?.refreshSeconds ?? 10) * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        do {
            let fresh = try await fetchMatches()
            matches = fresh
            await refreshDetails()
            lastUpdated = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // Ball-by-ball for watched live matches. A failure keeps the old detail.
    private func refreshDetails() async {
        let live = watchedMatches.filter(\.isLive)
        let results = await withTaskGroup(of: (String, LiveDetail?).self) { group in
            for m in live {
                group.addTask { (m.id, try? await fetchLiveDetail(m)) }
            }
            var out: [(String, LiveDetail?)] = []
            for await r in group { out.append(r) }
            return out
        }
        // Keep the old detail on a failed fetch, but not once a new innings has started.
        var next = details.filter { id, d in live.contains { $0.id == id && $0.period == d.period } }
        for (id, d) in results {
            guard var d else { continue }
            // Batters stay in the rows they had last time, so they don't swap places.
            if let old = next[id]?.batters.map(\.id) {
                // New batters go after the one who stayed; ties keep the fetched order.
                let rank = { (i: Int, b: BatterLine) in (old.firstIndex(of: b.id) ?? old.count, i) }
                d.batters = d.batters.enumerated().sorted { rank($0.0, $0.1) < rank($1.0, $1.1) }.map(\.element)
            }
            next[id] = d
        }
        details = next
    }
}
