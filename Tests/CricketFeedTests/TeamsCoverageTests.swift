import AppKit
import SwiftUI
import Testing
@testable import CricketFeed

// MARK: - Helpers for this file

// Pumps the run loop until `done` is true or the timeout passes.
@MainActor
private func waitUntil(_ timeout: TimeInterval = 2, _ done: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !done() && Date() < end { pump(0.02) }
    return done()
}

@MainActor
private func allSubviews(_ view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(allSubviews)
}

// Types into the picker's search box through the field editor, like a user would.
@MainActor
private func typeText(_ text: String, into hosting: NSView) {
    let field = allSubviews(hosting).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
    // The off-screen window never becomes key, but SwiftUI still gives the focused
    // field an editor (onAppear focuses it). Type into that editor.
    let editor = (field.currentEditor() as? NSTextView)
        ?? allSubviews(field).compactMap { $0 as? NSTextView }.first!
    editor.selectAll(nil)
    editor.insertText(text, replacementRange: editor.selectedRange())
    pump(0.1)
    hosting.layoutSubtreeIfNeeded()
}

private func side(_ id: String, _ name: String, logo: URL? = nil) -> Match.Side {
    Match.Side(id: id, name: name, short: "", score: "", logo: logo)
}

private func feedMatch(_ sides: [Match.Side]) -> Match {
    Match(id: "m", leagueID: "1", league: "Test", title: "m", detail: "", state: "in", stateLabel: "",
          summary: "", fullDescription: "", period: 1, sides: sides)
}

private let width: CGFloat = 320
// Search box is 28 high, then 8 spacing, so the list starts at y = 36.
// With one section showing: a label (~17) then the first row (~28).
private let firstRow = CGPoint(x: 120, y: 36 + 17 + 15)
private let clearButton = CGPoint(x: width - 15, y: 14)

@MainActor
private func picker(_ store: ScoreStore) -> NSHostingView<some View> {
    _ = StubURLProtocol.installed // team logos go to the stub, never the network
    let view = TeamPicker(store: store).frame(width: width, alignment: .top)
    return host(view, size: CGSize(width: width, height: 420), settle: 0.2)
}

// MARK: - Catalogue

@Suite struct TeamCatalogueTests {
    @Test func idsAreUniqueAndLogosMatchIDs() {
        // A repeated ID would star two teams at once.
        #expect(Set(TeamCatalogue.all.map(\.id)).count == TeamCatalogue.all.count)
        for team in TeamCatalogue.all {
            #expect(team.logo == URL(string: "https://a.espncdn.com/i/teamlogos/cricket/500/\(team.id).png"), "\(team.name)")
        }
        #expect(TeamCatalogue.international.first { $0.id == "1" }?.name == "England")
        #expect(TeamCatalogue.counties.first { $0.id == "1464" }?.name == "Yorkshire")
    }
}

// MARK: - Picker sections (plain logic)

@Suite struct TeamPickerSectionTests {
    private typealias Section = (title: String, teams: [TeamOption])
    private func titles(_ s: [Section]) -> [String] { s.map(\.title) }
    private func ids(_ s: [Section], _ title: String) -> [String] { s.first { $0.title == title }?.teams.map(\.id) ?? [] }

    private let feed = [feedMatch([
        side("777", "Zeta Qxq", logo: URL(string: "https://example.com/z.png")),
        side("778", "Alpha Qxq"),
        side("", "No ID Club"),
        side("779", "?"),
        side("780", ""),
        side("1", "England"), // already in the catalogue
    ])]

    @Test func feedTeamsDropSidesWithoutIDOrName() {
        #expect(TeamPicker.feedTeams(feed) == [
            TeamOption(id: "777", name: "Zeta Qxq", logo: URL(string: "https://example.com/z.png")),
            TeamOption(id: "778", name: "Alpha Qxq"),
            TeamOption(id: "1", name: "England"),
        ])
    }

    @Test func sectionsInOrderWithEachTeamOnceBelowYourTeams() {
        let england = TeamCatalogue.international[0]
        let s = TeamPicker.sections(pinned: [england], matches: feed, search: "")
        #expect(titles(s) == ["Your teams", "International", "English counties", "In the feed"])
        #expect(ids(s, "Your teams") == ["1"])
        // "Your teams" repeats England on purpose; it is still listed under International.
        #expect(ids(s, "International") == TeamCatalogue.international.map(\.id))
        #expect(ids(s, "English counties") == TeamCatalogue.counties.map(\.id))
        // Feed teams sorted by name, England not repeated.
        #expect(ids(s, "In the feed") == ["778", "777"])
    }

    @Test func emptySectionsAreHidden() {
        let s = TeamPicker.sections(pinned: [], matches: [], search: "")
        #expect(titles(s) == ["International", "English counties"])
    }

    @Test func searchIsCaseInsensitiveAndFiltersEverySection() {
        let mystery = TeamOption(id: "zz", name: "Mystery XI")
        let s = TeamPicker.sections(pinned: [mystery], matches: feed, search: "QXQ")
        #expect(titles(s) == ["In the feed"])
        #expect(ids(s, "In the feed") == ["778", "777"])
        let mine = TeamPicker.sections(pinned: [mystery], matches: feed, search: "myst")
        #expect(titles(mine) == ["Your teams"])
        #expect(ids(mine, "Your teams") == ["zz"])
    }

    @Test func searchWithNoHitsGivesNoSections() {
        #expect(TeamPicker.sections(pinned: [], matches: feed, search: "qqqqzz").isEmpty)
    }
}

// MARK: - Picker (hosted)

extension UITests {
    @MainActor @Suite struct TeamPickerTests {
        @Test func searchThenClickStarsTheOnlyMatch() {
            let temp = TempDefaults()
            let store = ScoreStore(defaults: temp.defaults)
            let v = picker(store)
            typeText("zimb", into: v)
            click(v, at: firstRow)
            #expect(waitUntil { store.favourites == ["9": "Zimbabwe"] })
            // Click again unstars it.
            click(v, at: firstRow)
            #expect(waitUntil { store.favourites.isEmpty })
        }

        @Test func clearButtonEmptiesSearch() {
            let temp = TempDefaults()
            let store = ScoreStore(defaults: temp.defaults)
            let v = picker(store)
            typeText("yorks", into: v)
            click(v, at: clearButton)
            // With search cleared, the first row is England again.
            click(v, at: firstRow)
            #expect(waitUntil { store.favourites == ["1": "England"] })
        }

        @Test func searchWithNoHitsLeavesNothingToStar() {
            let temp = TempDefaults()
            let store = ScoreStore(defaults: temp.defaults)
            let v = picker(store)
            typeText("qqqqzz", into: v)
            click(v, at: firstRow)
            pump(0.1)
            #expect(store.favourites.isEmpty)
        }

        @Test func pinnedTeamsStayPutWhenUnstarred() {
            let temp = TempDefaults()
            let store = ScoreStore(defaults: temp.defaults)
            // One known team, one unknown team (no logo, name kept from favourites).
            store.favourites = ["1": "England", "zz": "Mystery XI"]
            let v = picker(store)
            // "Your teams" sorted: England, Mystery XI. Unstar England.
            click(v, at: firstRow)
            #expect(waitUntil { store.favourites == ["zz": "Mystery XI"] })
            // Row did not move, so the same spot stars it again.
            click(v, at: firstRow)
            #expect(waitUntil { store.favourites == ["1": "England", "zz": "Mystery XI"] })
            // Unknown team appears under Your teams and can be unstarred by search.
            typeText("mystery", into: v)
            click(v, at: firstRow)
            #expect(waitUntil { store.favourites == ["1": "England"] })
        }
    }
}
