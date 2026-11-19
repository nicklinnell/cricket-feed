import Foundation
import Testing
@testable import CricketFeed

@Suite struct FeedParsing {
    func parse(_ competitor: String, event: String = #""id":"9","name":"A v B""#) throws -> [Match] {
        try parseMatches(Data("""
        {"scores":[{"leagues":[{"id":"8048","name":"Big Bash"}],
          "events":[{\(event),"competitions":[{"competitors":[\(competitor)]}]}]}]}
        """.utf8))
    }

    @Test func teamIDAsText() throws {
        #expect(try parse(#"{"team":{"id":"1"}}"#)[0].sides[0].id == "1")
    }

    @Test func teamIDAsNumber() throws {
        #expect(try parse(#"{"team":{"id":1}}"#)[0].sides[0].id == "1")
    }

    @Test func oddTeamIDDoesNotFailTheFeed() throws {
        let m = try parse(#"{"team":{"id":{"x":1},"displayName":"England"}}"#)
        #expect(m[0].sides[0].id == "")
        #expect(m[0].sides[0].name == "England")
    }

    @Test func missingFieldsGetDefaults() throws {
        let m = try parse(#"{}"#, event: #""id":"9""#)[0]
        #expect(m.league == "Big Bash")
        #expect(m.leagueID == "8048")
        #expect(m.period == 1)
        #expect(m.sides[0].name == "?")
        #expect(m.title == "?")
    }

    @Test func competitionStatusBeatsEventStatus() throws {
        let m = try parseMatches(Data("""
        {"scores":[{"events":[{"id":"9","status":{"type":{"state":"pre"}},
          "competitions":[{"status":{"period":2,"type":{"state":"in"}}}]}]}]}
        """.utf8))[0]
        #expect(m.isLive)
        #expect(m.period == 2)
    }
}
