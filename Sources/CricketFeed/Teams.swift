import SwiftUI

// A team you can star. Matched to the feed by ESPN team ID.
struct TeamOption: Hashable {
    let id: String
    let name: String
    var logo: URL? = nil
}

// Names and IDs checked against ESPN's team records (core.espnuk.org/v2/sports/cricket/teams/<id>).
// Logos live at a.espncdn.com/i/teamlogos/cricket/500/<id>.png.
enum TeamCatalogue {
    static let international: [TeamOption] = teams([
        (1, "England"), (2, "Australia"), (6, "India"), (3, "South Africa"), (5, "New Zealand"),
        (7, "Pakistan"), (8, "Sri Lanka"), (4, "West Indies"), (25, "Bangladesh"), (40, "Afghanistan"),
        (9, "Zimbabwe"), (29, "Ireland"), (30, "Scotland"), (15, "Netherlands"), (33, "Nepal"),
        (37, "Oman"), (27, "United Arab Emirates"), (11, "United States of America"), (28, "Namibia"),
        (17, "Canada"), (20, "Papua New Guinea"), (19, "Hong Kong"),
    ])

    static let counties: [TeamOption] = teams([
        (904, "Derbyshire"), (924, "Durham"), (984, "Essex"), (1029, "Glamorgan"), (1034, "Gloucestershire"),
        (1051, "Hampshire"), (1098, "Kent"), (1116, "Lancashire"), (1133, "Leicestershire"), (1190, "Middlesex"),
        (1221, "Northamptonshire"), (1231, "Nottinghamshire"), (1333, "Somerset"), (1358, "Surrey"),
        (1371, "Sussex"), (1428, "Warwickshire"), (1458, "Worcestershire"), (1464, "Yorkshire"),
    ])

    static let all = international + counties

    private static func teams(_ list: [(Int, String)]) -> [TeamOption] {
        list.map { TeamOption(id: String($0.0), name: $0.1, logo: URL(string: "https://a.espncdn.com/i/teamlogos/cricket/500/\($0.0).png")) }
    }
}

struct TeamPicker: View {
    @ObservedObject var store: ScoreStore
    var maxHeight: CGFloat = 320
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    // "Your teams" as it was when the screen opened. Starring or unstarring
    // changes only the star, so rows never move under the pointer.
    @State private var pinned: [TeamOption]

    init(store: ScoreStore, maxHeight: CGFloat = 320) {
        self.store = store
        self.maxHeight = maxHeight
        let pool = TeamCatalogue.all + Self.feedTeams(store.matches)
        _pinned = State(initialValue: store.favourites
            .map { id, name in pool.first { $0.id == id } ?? TeamOption(id: id, name: name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    // Every team in today's feed that has an ID (needed to star it).
    static func feedTeams(_ matches: [Match]) -> [TeamOption] {
        matches.flatMap(\.sides)
            .filter { !$0.id.isEmpty && !$0.name.isEmpty && $0.name != "?" }
            .map { TeamOption(id: $0.id, name: $0.name, logo: $0.logo) }
    }

    // Your teams first, then the fixed lists, then anyone else in the feed.
    private var sections: [(title: String, teams: [TeamOption])] {
        Self.sections(pinned: pinned, matches: store.matches, search: search)
    }

    static func sections(pinned: [TeamOption], matches: [Match], search: String) -> [(title: String, teams: [TeamOption])] {
        var seen = Set<String>()
        func fresh(_ list: [TeamOption]) -> [TeamOption] {
            list.filter { seen.insert($0.id).inserted }
        }
        let other = feedTeams(matches)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // "Your teams" repeats rows from below on purpose.
        let all: [(String, [TeamOption])] = [
            ("Your teams", pinned),
            ("International", fresh(TeamCatalogue.international)),
            ("English counties", fresh(TeamCatalogue.counties)),
            ("In the feed", fresh(other)),
        ]
        return all.compactMap { title, teams in
            let shown = search.isEmpty ? teams : teams.filter { $0.name.localizedCaseInsensitiveContains(search) }
            return shown.isEmpty ? nil : (title, shown)
        }
    }

    private struct Row {
        let id: String
        let title: String
        var team: TeamOption? = nil
        var first = false
    }

    private var rows: [Row] {
        sections.enumerated().flatMap { i, section in
            [Row(id: "#" + section.title, title: section.title, first: i == 0)]
                + section.teams.map { Row(id: section.title + "/" + $0.id, title: section.title, team: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SearchField(prompt: "Search teams", text: $search, focused: $searchFocused)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if sections.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "No results",
                            message: "Nothing matches \u{201C}\(search)\u{201D}.",
                            tint: Theme.meta
                        )
                    }
                    // One flat list with section-scoped IDs: a team can sit in two sections
                    // ("Your teams" and "International"), and a shared ID makes one row vanish.
                    ForEach(rows, id: \.id) { row in
                        if let team = row.team {
                            TeamRow(team: team, selected: store.favourites[team.id] != nil) {
                                store.toggleFavourite(team)
                            }
                        } else {
                            SectionLabel(title: row.title, first: row.first)
                        }
                    }
                }
                .padding(.bottom, 18) // last row can scroll clear of the fade
            }
            .frame(height: min(320, maxHeight))
            .bottomFade(true)
            Toggle("Auto-watch my teams' matches", isOn: $store.autoWatch)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: Theme.bodySize))
                .padding(.horizontal, 4)
                .help(store.autoWatch
                      ? "Their matches go in your panel without picking them"
                      : "Their matches only go to the top of Pick matches")
            Toggle("Notify me of wickets and milestones", isOn: $store.notifyMilestones)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: Theme.bodySize))
                .padding(.horizontal, 4)
                .help("Wickets, every 100 runs, batters' 50s and 100s, and results")
        }
        .onAppear { searchFocused = true }
    }
}

struct TeamRow: View {
    let team: TeamOption
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                Group {
                    if let logo = team.logo { TeamFlag(url: logo) } else { Color.clear }
                }
                .frame(width: 20, height: 14)
                Text(team.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: selected ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.meta))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PickerRowStyle(selected: selected))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(team.name)
        .accessibilityHint(selected ? "Remove from favourite teams" : "Add to favourite teams")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// Small capitals heading above a group of rows ("LIVE", "YOUR TEAMS").
struct SectionLabel: View {
    let title: String
    let first: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Theme.meta)
            .padding(.horizontal, 8)
            .padding(.top, first ? 2 : 10)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.meta)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.meta)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 0.5))
    }
}
