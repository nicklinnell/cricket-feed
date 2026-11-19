import Testing
@testable import CricketFeed

@MainActor @Suite struct Watching {
    let temp = TempDefaults()
    var store: ScoreStore { ScoreStore(defaults: temp.defaults) }

    @Test func autoWatchIsOnByDefault() {
        #expect(store.autoWatch)
    }

    @Test func favouriteMatchesShowUpAndComeFirst() {
        let s = store
        s.favourites = ["1": "England"]
        s.matches = [match("picked", teams: ["2", "3"]), match("fav", teams: ["4", "1"]), match("other", teams: ["5", "6"])]
        s.watched = ["picked"]
        #expect(s.watchedMatches.map(\.id) == ["fav", "picked"])
        s.autoWatch = false
        #expect(s.watchedMatches.map(\.id) == ["picked"])
    }

    // By ID only: an empty ID never matches and names don't matter.
    @Test func matchesByTeamID() {
        let s = store
        s.favourites = ["1": "England"]
        #expect(!s.hasFavourite(match("w", teams: ["1001"])))
        s.favourites = ["": "Nobody"]
        #expect(!s.hasFavourite(match("blank", teams: [""])))
    }

    @Test func stoppedMatchStaysStoppedUntilTickedAgain() {
        let s = store
        s.favourites = ["1": "England"]
        let m = match("fav", teams: ["1", "2"])
        #expect(s.isWatched(m))
        s.toggle(m)
        #expect(!s.isWatched(m))
        #expect(s.hidden == ["fav"])
        s.toggle(m)
        #expect(s.isWatched(m))
        #expect(s.hidden.isEmpty)
        // A tick is a real pick, so it stays after unstarring the team.
        s.favourites = [:]
        #expect(s.isWatched(m))
    }

    // Users' picks survive upgrades only if these keys never change.
    @Test func savesUnderStableKeys() {
        let s = store
        s.toggle(match("m1"))
        s.favourites = ["1": "England"]
        s.autoWatch = false
        s.toggleStats(match("m2"))
        let d = temp.defaults
        #expect(d.stringArray(forKey: "watchedMatchIDs") == ["m1"])
        #expect(d.dictionary(forKey: "favouriteTeamIDs") as? [String: String] == ["1": "England"])
        #expect(d.object(forKey: "autoWatchFavourites") as? Bool == false)
        #expect(d.stringArray(forKey: "statsOpenMatchIDs") == ["m2"])
        s.toggle(match("m1"))
        #expect(d.stringArray(forKey: "hiddenMatchIDs") == ["m1"])
        // And a fresh store reads them back.
        let again = ScoreStore(defaults: d)
        #expect(again.hidden == ["m1"])
        #expect(!again.autoWatch)
    }
}
