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

    // Favourite teams: ESPN team ID -> name. IDs, not names, so a renamed or
    // differently spelled team still matches. Name is for showing in the list.
    @Published var favourites: [String: String] {
        didSet { UserDefaults.standard.set(favourites, forKey: Self.favouritesKey) }
    }

    // When on, favourite teams' matches go in the panel without being picked.
    @Published var autoWatch: Bool {
        didSet { UserDefaults.standard.set(autoWatch, forKey: Self.autoWatchKey) }
    }

    // Matches the user stopped watching. Keeps auto-watch from adding them back.
    @Published var hidden: Set<String> {
        didSet { UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey) }
    }

    static let watchedKey = "watchedMatchIDs"
    static let statsOpenKey = "statsOpenMatchIDs"
    static let favouritesKey = "favouriteTeamIDs"
    static let autoWatchKey = "autoWatchFavourites"
    static let hiddenKey = "hiddenMatchIDs"
    let refreshSeconds: UInt64 = 10

    private var loop: Task<Void, Never>?

    init() {
        watched = Set(UserDefaults.standard.stringArray(forKey: Self.watchedKey) ?? [])
        statsOpen = Set(UserDefaults.standard.stringArray(forKey: Self.statsOpenKey) ?? [])
        favourites = UserDefaults.standard.dictionary(forKey: Self.favouritesKey) as? [String: String] ?? [:]
        // On unless turned off. bool(forKey:) also reads "NO" passed on the command line.
        autoWatch = UserDefaults.standard.object(forKey: Self.autoWatchKey) == nil || UserDefaults.standard.bool(forKey: Self.autoWatchKey)
        hidden = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    // Anything that could put a card on screen: picked matches or auto-watched teams.
    var followingAnything: Bool { !watched.isEmpty || autoWatchingTeams }

    var autoWatchingTeams: Bool { autoWatch && !favourites.isEmpty }

    // Favourite teams' matches first; otherwise the feed's order.
    var watchedMatches: [Match] {
        let shown = matches.filter(isWatched)
        return shown.filter(hasFavourite) + shown.filter { !hasFavourite($0) }
    }

    // Picked by hand, or auto-watched for a favourite team and not stopped.
    func isWatched(_ match: Match) -> Bool {
        watched.contains(match.id) || (autoWatch && hasFavourite(match) && !hidden.contains(match.id))
    }

    func hasFavourite(_ match: Match) -> Bool {
        match.sides.contains { isFavourite(id: $0.id, name: $0.name) }
    }

    // By ID. Name only as a fallback when the feed gives no ID; exact (case aside),
    // so "England" never catches "England Women".
    func isFavourite(id: String, name: String) -> Bool {
        if !id.isEmpty { return favourites[id] != nil }
        return favourites.values.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    func toggleFavourite(_ team: TeamOption) {
        if favourites[team.id] != nil {
            favourites[team.id] = nil
        } else {
            favourites[team.id] = team.name
            // Starring a team means "show me their games", including ones stopped before.
            let theirs = matches.filter { m in m.sides.contains { $0.id == team.id } }.map(\.id)
            hidden.subtract(theirs)
        }
    }

    func toggle(_ match: Match) {
        if isWatched(match) {
            watched.remove(match.id)
            // Always remembered, so it stays gone even if a favourite is named in it later.
            hidden.insert(match.id)
        } else {
            // Always a real pick, so it stays even if the team is unstarred later.
            hidden.remove(match.id)
            watched.insert(match.id)
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
