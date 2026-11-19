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
    @Test func listsAreCompleteWithLogos() {
        #expect(TeamCatalogue.international.count == 22)
        #expect(TeamCatalogue.counties.count == 18)
        #expect(TeamCatalogue.all == TeamCatalogue.international + TeamCatalogue.counties)
        #expect(Set(TeamCatalogue.all.map(\.id)).count == TeamCatalogue.all.count)
        let england = TeamCatalogue.international[0]
        #expect(england == TeamOption(id: "1", name: "England",
                                      logo: URL(string: "https://a.espncdn.com/i/teamlogos/cricket/500/1.png")))
        #expect(TeamCatalogue.counties.last?.name == "Yorkshire")
        #expect(TeamOption(id: "x", name: "X").logo == nil)
    }
}

// MARK: - Picker

@MainActor @Suite(.serialized) struct TeamPickerTests {
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

    @Test func noResultsShowsEmptyStateAndNothingToClick() {
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

    @Test func feedTeamsAreListedSortedAndStarrable() {
        let temp = TempDefaults()
        let store = ScoreStore(defaults: temp.defaults)
        store.matches = [feedMatch([
            side("777", "Zeta Qxq", logo: URL(string: "https://example.com/z.png")),
            side("778", "Alpha Qxq"),
            side("", "No ID Club"),
            side("779", "?"),
            side("1", "England"), // already in the catalogue
        ])]
        let v = picker(store)
        // Feed teams are sorted by name, so Alpha comes first.
        typeText("qxq", into: v)
        click(v, at: firstRow)
        #expect(waitUntil { store.favourites == ["778": "Alpha Qxq"] })
        // Teams without a usable ID or name are not offered.
        for search in ["no id", "?"] {
            typeText(search, into: v)
            click(v, at: firstRow)
            pump(0.1)
            #expect(store.favourites == ["778": "Alpha Qxq"])
        }
        // England is in the feed too but only listed once: same number of row
        // buttons as a search with one hit.
        func buttons() -> Int { allSubviews(v).filter { String(describing: Swift.type(of: $0)) == "KeyViewProxy" }.count }
        typeText("zimbabwe", into: v)
        let one = buttons()
        typeText("england", into: v)
        #expect(buttons() == one)
        click(v, at: firstRow)
        #expect(waitUntil { store.favourites == ["778": "Alpha Qxq", "1": "England"] })
    }

    @Test func autoWatchSwitchFlipsAndSaves() throws {
        let temp = TempDefaults()
        let store = ScoreStore(defaults: temp.defaults)
        #expect(store.autoWatch)
        let v = picker(store)
        // A real mouse click on the AppKit switch ends the test process, so press it
        // through accessibility (VoiceOver's route). It returns false but does flip it.
        let sw = try #require(allSubviews(v).first { String(describing: Swift.type(of: $0)) == "PlatformSwitch" })
        _ = sw.accessibilityPerformPress()
        #expect(waitUntil { !store.autoWatch })
        #expect(temp.defaults.bool(forKey: ScoreStore.autoWatchKey) == false)
        _ = sw.accessibilityPerformPress()
        #expect(waitUntil { store.autoWatch })
    }

    @Test func sectionLabelFirstHasLessTopSpace() {
        func height(_ label: SectionLabel) -> CGFloat {
            host(label, size: CGSize(width: 200, height: 40)).fittingSize.height
        }
        let plain = height(SectionLabel(title: "Live"))
        #expect(plain == height(SectionLabel(title: "Live", first: false)))
        #expect(plain - height(SectionLabel(title: "Live", first: true)) == 8)
    }
}
