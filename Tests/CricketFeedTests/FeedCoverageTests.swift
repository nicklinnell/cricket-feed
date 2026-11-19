import Foundation
import Testing
@testable import CricketFeed

@Suite struct FeedModel {
    @Test func cricinfoURLUsesMatchID() {
        #expect(match("1415703").cricinfoURL.absoluteString
            == "https://www.espncricinfo.com/ci/engine/match/1415703.html")
    }

    @Test(arguments: [("in", true), ("post", false), ("pre", false), ("", false)])
    func isLiveOnlyWhenInPlay(state: String, live: Bool) {
        let m = Match(id: "1", leagueID: "1", league: "", title: "", detail: "", state: state,
                      stateLabel: "", summary: "", fullDescription: "", period: 1, sides: [])
        #expect(m.isLive == live)
    }

    @Test func badStatusDescribesHTTPCode() {
        let error: Error = FeedError.badStatus(503)
        #expect(error.localizedDescription == "Feed returned HTTP 503")
        #expect(FeedError.badStatus(404).errorDescription == "Feed returned HTTP 404")
    }

    @Test func fullFeedFieldsCarryThrough() throws {
        let m = try parseMatches(Data("""
        {"scores":[{"leagues":[{"id":"8048","name":"Big Bash"}],
          "events":[{"id":"9","name":"Heat v Stars","description":"5th Match",
            "competitions":[{"description":"5th Match, Brisbane",
              "status":{"summary":"Heat need 20 runs","period":2,"type":{"state":"in","description":"Live"}},
              "competitors":[
                {"score":"150/4","team":{"id":"1","displayName":"Heat","abbreviation":"HEA","logo":"https://a.espncdn.com/heat.png"}},
                {"score":"169/7","team":{"id":2,"displayName":"Stars","abbreviation":"STA"}}]}]}]}]}
        """.utf8))[0]
        #expect(m.title == "Heat v Stars")
        #expect(m.detail == "5th Match, Brisbane")
        #expect(m.fullDescription == "5th Match")
        #expect(m.stateLabel == "Live")
        #expect(m.summary == "Heat need 20 runs")
        #expect(m.sides.map(\.id) == ["1", "2"])
        #expect(m.sides.map(\.short) == ["HEA", "STA"])
        #expect(m.sides.map(\.score) == ["150/4", "169/7"])
        #expect(m.sides[0].logo == URL(string: "https://a.espncdn.com/heat.png"))
        #expect(m.sides[1].logo == nil)
    }

    @Test func titleFallsBackToTeamNames() throws {
        let m = try parseMatches(Data("""
        {"scores":[{"events":[{"id":"9","competitions":[{"competitors":[
          {"team":{"displayName":"England"}},{"team":{"displayName":"India"}}]}]}]}]}
        """.utf8))[0]
        #expect(m.title == "England v India")
        #expect(m.league == "")
        #expect(m.leagueID == "")
    }

    @Test func blockWithNoEventsGivesNoMatches() throws {
        #expect(try parseMatches(Data(#"{"scores":[{"leagues":[{"id":"1"}]}]}"#.utf8)).isEmpty)
    }
}

extension NetworkTests {
    @Suite struct FeedFetching {
        @Test func okResponseIsParsed() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: scorePanelURL.absoluteString, json: """
            {"scores":[{"leagues":[{"id":"8048","name":"Big Bash"}],
              "events":[{"id":"9","name":"Heat v Stars"}]}]}
            """)
            let matches = try await fetchMatches()
            #expect(matches.map(\.id) == ["9"])
            #expect(matches[0].league == "Big Bash")
            // Ignore team logos other tests may load at the same time.
            #expect(StubURLProtocol.requests.filter { $0.host != "a.espncdn.com" } == [scorePanelURL])
        }

        @Test func nonOKResponseThrowsBadStatus() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: scorePanelURL.absoluteString, status: 500, json: "{}")
            do {
                _ = try await fetchMatches()
                Issue.record("expected an error")
            } catch let FeedError.badStatus(code) {
                #expect(code == 500)
            }
        }

        @Test func badJSONThrowsDecodingError() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: scorePanelURL.absoluteString, json: "not json")
            await #expect(throws: DecodingError.self) { try await fetchMatches() }
        }

        @Test func networkFailurePassesThrough() async throws {
            StubURLProtocol.reset()
            await #expect(throws: URLError.self) { try await fetchMatches() }
        }
    }
}
