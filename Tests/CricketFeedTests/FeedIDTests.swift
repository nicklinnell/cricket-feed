import Foundation
import Testing
@testable import CricketFeed

// One odd ID must never drop every match in the feed.
@Suite struct FeedIDs {
    func parse(_ events: String, league: String = #"{"id":"8048","name":"Big Bash"}"#) throws -> [Match] {
        try parseMatches(Data(#"{"scores":[{"leagues":[\#(league)],"events":[\#(events)]}]}"#.utf8))
    }

    @Test func eventIDAsNumber() throws {
        #expect(try parse(#"{"id":9,"name":"A v B"}"#).map(\.id) == ["9"])
    }

    @Test func eventWithNoUsableIDIsSkippedNotFatal() throws {
        let m = try parse(#"{"name":"no id"},{"id":"","name":"blank"},{"id":{"x":1}},{"id":"7","name":"ok"}"#)
        #expect(m.map(\.id) == ["7"])
    }

    @Test func leagueIDAsNumberOrMissing() throws {
        #expect(try parse(#"{"id":"1"}"#, league: #"{"id":8048,"name":"BBL"}"#)[0].leagueID == "8048")
        let m = try parse(#"{"id":"1"}"#, league: #"{"name":"BBL"}"#)[0]
        #expect(m.leagueID == "")
        #expect(m.league == "BBL")
    }

    @Test func playByPlayPageWithMissingFieldsIsEmpty() throws {
        let page = try decode(PBPResponse.self, #"{"commentary":{}}"#).commentary
        #expect(page.pageCount == nil)
        #expect(page.items == nil)
    }
}

extension NetworkTests {
    @Suite struct PlayByPlayMissingFields {
        @Test func pageWithNoCountGivesNoDetail() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: "https://site.web.api.espn.com/apis/site/v2/sports/cricket/", json: #"{"commentary":{}}"#)
            #expect(try await fetchLiveDetail(match("42")) == nil)
        }
    }
}
