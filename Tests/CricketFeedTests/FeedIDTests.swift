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

        // A later page with no items adds nothing but doesn't lose page 1's balls.
        @Test func laterPageWithNoItemsKeepsEarlierBalls() async throws {
            StubURLProtocol.reset()
            let base = "https://site.web.api.espn.com/apis/site/v2/sports/cricket/"
            StubURLProtocol.on(prefix: base, json: #"{"commentary":{"pageCount":2}}"#)
            StubURLProtocol.on({ $0.absoluteString.hasPrefix(base) && $0.absoluteString.contains("page=1") }) { _ in
                (200, Data(#"{"commentary":{"pageCount":2,"items":[\#(ball(over: 1, runs: 4))]}}"#.utf8))
            }
            let d = try await fetchLiveDetail(match("42"))
            #expect(d?.overs.map(\.number) == [1])
            #expect(d?.overs.first?.runs == 4)
        }
    }
}
