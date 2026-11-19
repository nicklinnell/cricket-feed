import SwiftUI
import AppKit

struct ContentView: View {
    enum Mode {
        case scores, matches, teams

        var title: String {
            switch self {
            case .scores: "Cricket"
            case .matches: "Pick matches"
            case .teams: "Favourite teams"
            }
        }
    }

    // What the scores list shows instead of cards, or that it shows cards.
    struct EmptyState: Equatable {
        let symbol: String
        let title: String
        let message: String
        // Invitations offer the match picker (blue); problems don't (grey).
        let offersPicker: Bool
    }

    enum ListContent: Equatable {
        case empty(EmptyState)
        case loading(placeholders: Int)
        case cards
    }

    @ObservedObject var store: ScoreStore
    @ObservedObject var room: PanelRoom
    var onSizeChange: (CGSize) -> Void = { _ in }
    @State private var mode = Mode.scores
    @State private var refreshing = false
    @State private var spin = 0.0
    @State private var listHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch mode {
            case .matches: MatchPicker(store: store, maxHeight: room.maxListHeight - 36)
            case .teams: TeamPicker(store: store, maxHeight: room.maxListHeight - 64)
            case .scores: watchedList
            }
            if Self.showsFooter(store, mode: mode) { footer }
        }
        .padding(12)
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(mode.title)
                .font(.system(size: Theme.titleSize, weight: .semibold, design: .rounded))
            Spacer()
            if mode != .scores {
                Button("Done") { mode = .scores }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    Task { await refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(spin))
                }
                .buttonStyle(IconButtonStyle())
                .help("Refresh now")
                .accessibilityLabel("Refresh now")
                .disabled(refreshing)
                Button {
                    mode = .teams
                } label: { Image(systemName: "star") }
                .buttonStyle(IconButtonStyle())
                .help("Favourite teams")
                .accessibilityLabel("Favourite teams")
                Button {
                    mode = .matches
                } label: { Image(systemName: "plus") }
                .buttonStyle(IconButtonStyle())
                .help("Pick matches")
                .accessibilityLabel("Pick matches")
            }
        }
        .frame(height: 24)
    }

    private func refreshNow() async {
        refreshing = true
        if !reduceMotion { withAnimation(.linear(duration: 0.6)) { spin += 360 } }
        await store.refresh()
        refreshing = false
    }

    static func listContent(_ store: ScoreStore) -> ListContent {
        if !store.followingAnything {
            return .empty(EmptyState(
                symbol: "figure.cricket",
                title: "No matches yet",
                message: store.favourites.isEmpty
                    ? "Pick the games you want to follow, or star your favourite teams, and their scores will show here."
                    : "Pick the games you want to follow. Your teams' games are at the top of the list.",
                offersPicker: true))
        }
        if store.lastUpdated == nil && store.error == nil {
            return .loading(placeholders: min(max(store.watched.count + (store.autoWatchingTeams ? 1 : 0), 1), 2))
        }
        if !store.watchedMatches.isEmpty { return .cards }
        if store.lastUpdated == nil {
            return .empty(EmptyState(symbol: "wifi.slash", title: "Can't reach the score feed",
                                     message: "Will keep trying every few seconds.", offersPicker: false))
        }
        return .empty(EmptyState(
            symbol: "calendar.badge.clock",
            title: "Nothing on right now",
            message: !store.autoWatchingTeams
                ? "Your picked matches aren't in the feed at the moment."
                : store.matches.contains(where: store.hasFavourite)
                    ? "You've stopped watching your teams' matches."
                    : "None of your teams are playing right now.",
            offersPicker: true))
    }

    // "Updated 11:28" means nothing with no matches picked.
    static func showsFooter(_ store: ScoreStore, mode: Mode) -> Bool {
        store.followingAnything || mode != .scores || store.error != nil
    }

    static func footerText(error: String?, lastUpdated: Date?) -> String {
        if error != nil { return lastUpdated.map { "Offline · last update \(short($0))" } ?? "Offline" }
        if let t = lastUpdated { return "Updated \(short(t))" }
        return "Fetching scores"
    }

    @ViewBuilder
    private var watchedList: some View {
        switch Self.listContent(store) {
        case .empty(let empty):
            EmptyStateView(
                symbol: empty.symbol,
                title: empty.title,
                message: empty.message,
                action: empty.offersPicker ? ("Pick matches", { mode = .matches }) : nil,
                tint: empty.offersPicker ? .accentColor : Theme.meta
            )
        case .loading(let placeholders):
            VStack(spacing: 10) {
                ForEach(0..<placeholders, id: \.self) { _ in SkeletonCard() }
            }
            .frame(maxHeight: room.maxListHeight, alignment: .top)
            .clipped()
        case .cards:
            // Scrolls only once the cards would be taller than the screen allows.
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.watchedMatches) { match in
                        MatchCard(match: match, detail: store.details[match.id],
                                  statsOpen: store.statsOpen.contains(match.id),
                                  toggleStats: { store.toggleStats(match) })
                            .contextMenu { MatchCardMenu(match: match, store: store) }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                .padding(.bottom, scrolls ? 18 : 0)
            }
            .scrollDisabled(!scrolls)
            .frame(height: min(max(listHeight, 1), room.maxListHeight))
            // Soft fade at the bottom so a cut-off card reads as "more below".
            .bottomFade(scrolls)
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            let text = Self.footerText(error: store.error, lastUpdated: store.lastUpdated)
            if let err = store.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.pausedInk)
                Text(text)
                    .foregroundStyle(Theme.pausedInk)
                    .help(err)
                    .accessibilityHint(err)
            } else {
                if store.lastUpdated == nil { ProgressView().controlSize(.mini) }
                Text(text)
            }
            Spacer()
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(Theme.meta)
        .lineLimit(1)
        .padding(.horizontal, 4)
    }

    private var scrolls: Bool { listHeight > room.maxListHeight }

    static func short(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}

struct MatchCard: View {
    let match: Match
    var detail: LiveDetail?
    var statsOpen = false
    var toggleStats: () -> Void = {}

    private var phase: MatchPhase { MatchPhase(match) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // Teams and scores: the part the eye should hit first.
            VStack(alignment: .leading, spacing: 6) {
                if match.sides.isEmpty {
                    Text(match.title)
                        .font(.system(size: Theme.teamSize, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(match.sides, id: \.self) { side in
                    SideRow(side: side, batting: battingSide == side, quiet: battingSide != nil && battingSide != side)
                }
            }
            .padding(.top, 12)
            if !summaryText.isEmpty || !(liveDetail?.overs.isEmpty ?? true) || !(liveDetail?.rates.isEmpty ?? true) {
                VStack(alignment: .leading, spacing: 6) {
                    if !summaryText.isEmpty {
                        Text(summaryText)
                            .font(.system(size: Theme.bodySize, weight: summaryStrong ? .medium : .regular))
                            .foregroundStyle(summaryStrong ? Color.primary : Theme.meta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let live = liveDetail, !live.rates.isEmpty {
                        RatesRow(rates: live.rates)
                    }
                    if let overs = liveDetail?.overs, !overs.isEmpty {
                        OversLine(overs: overs)
                            .padding(.top, 2)
                    }
                    if let live = liveDetail, !live.batters.isEmpty || !live.bowlers.isEmpty {
                        PlayersSection(detail: live, open: statsOpen, toggle: toggleStats)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Hairline().offset(y: -0.5) }
                .padding(.top, 10)
            }
        }
        .padding(12)
        .cardBackground(prominent: phase == .live || phase == .paused)
        .help(match.fullDescription)
    }

    // "1st Test (D/N) · Johannesburg"   [LIVE]
    // "Bangladesh tour of South Africa 2026/27"   (date first for upcoming games)
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                (Text(title)
                    .foregroundStyle(.primary)
                 + Text(city.isEmpty ? "" : (title.isEmpty ? city : "  ·  " + city))
                    .foregroundStyle(Theme.meta))
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusPill(match: match)
            }
            if !secondLine.isEmpty {
                Text(secondLine)
                    .font(.system(size: Theme.metaSize))
                    .foregroundStyle(Theme.meta)
                    .lineLimit(1)
            }
        }
        // VoiceOver gets the full description (with the date), not the trimmed lines.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([match.fullDescription.isEmpty ? title : match.fullDescription, match.stateLabel].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    var title: String {
        match.detail.isEmpty ? match.league : match.detail + dayNight
    }

    var secondLine: String {
        let league = match.detail.isEmpty ? "" : match.league
        if phase == .upcoming, !date.isEmpty {
            return [date, league].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        }
        return league
    }

    // Ball-by-ball extras only while the match is in play (live or a break).
    // Hidden as soon as a new innings starts, so last innings' players never sit under the new score.
    var liveDetail: LiveDetail? {
        match.isLive && detail?.period == match.period ? detail : nil
    }

    // "Australia need 126 runs in 63 balls." beats the feed's shorter summary.
    var summaryText: String {
        liveDetail?.chase ?? match.summary
    }

    // Results and live play read as headline text; toss news and start times stay quiet.
    var summaryStrong: Bool {
        switch phase {
        case .finished: true
        case .live, .paused: !match.summary.localizedCaseInsensitiveContains("won toss") || liveDetail?.chase != nil
        case .upcoming: false
        }
    }

    // "3rd ODI (D/N), England tour of Australia at Hobart, Nov 18 2026"
    //  -> dayNight " (D/N)", venue "Hobart, Nov 18 2026".
    var dayNight: String {
        let full = match.fullDescription
        guard full.hasPrefix(match.detail) else { return "" }
        let rest = full.dropFirst(match.detail.count)
        guard rest.hasPrefix(" ("), let close = rest.firstIndex(of: ")") else { return "" }
        return String(rest[...close])
    }

    var venue: String {
        guard let r = match.fullDescription.range(of: " at ", options: .backwards) else { return "" }
        return String(match.fullDescription[r.upperBound...])
    }

    // "Hobart, Nov 18 2026" -> city "Hobart", date "Nov 18 2026". No comma: all of it is the city.
    var city: String {
        guard let comma = venue.firstIndex(of: ",") else { return venue }
        return String(venue[..<comma])
    }

    var date: String {
        guard let comma = venue.firstIndex(of: ",") else { return "" }
        return venue[venue.index(after: comma)...].trimmingCharacters(in: .whitespaces)
    }

    // Best guess: in live play, the only side whose score has overs in brackets is batting.
    var battingSide: Match.Side? {
        guard phase == .live || (phase == .paused && !match.stateLabel.localizedCaseInsensitiveContains("innings")) else { return nil }
        let withOvers = match.sides.filter { !ScoreParts($0.score).detail.isEmpty }
        return withOvers.count == 1 ? withOvers[0] : nil
    }
}

// Right-click menu on a card. Own view so tests can host it and click its buttons.
// Opens links through the environment's openURL (the default browser), which tests replace.
struct MatchCardMenu: View {
    let match: Match
    @ObservedObject var store: ScoreStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Open on Cricinfo") { openURL(match.cricinfoURL) }
        Button("Stop watching") { store.toggle(match) }
    }
}

struct MatchPicker: View {
    @ObservedObject var store: ScoreStore
    var maxHeight: CGFloat = 320
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private static func rank(_ m: Match) -> Int {
        switch m.state { case "in": 0; case "pre": 1; default: 2 }
    }

    // The picker's sections, in order, with the matches that survive the search.
    static func sections(_ matches: [Match], search: String, favourite: (Match) -> Bool) -> [(title: String, matches: [Match])] {
        var filtered = matches.sorted { a, b in
            // Live first, then upcoming, then finished.
            rank(a) == rank(b) ? a.title < b.title : rank(a) < rank(b)
        }
        if !search.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(search) ||
                $0.league.localizedCaseInsensitiveContains(search)
            }
        }
        // Favourite teams' matches get their own section at the top.
        let groups = Dictionary(grouping: filtered) { favourite($0) ? -1 : rank($0) }
        return [(-1, "Your teams"), (0, "Live"), (1, "Upcoming"), (2, "Finished")].compactMap { key, title in
            guard let m = groups[key], !m.isEmpty else { return nil }
            return (title, m)
        }
    }

    // What to show when there are no rows: still loading, feed down, feed empty or no search results.
    static func emptyState(hasMatches: Bool, loaded: Bool, error: String?, search: String) -> (symbol: String, title: String, message: String) {
        if !hasMatches && !loaded {
            return error == nil
                ? ("hourglass", "Fetching matches", "One moment.")
                : ("wifi.slash", "Can't reach the score feed", "Will keep trying every few seconds.")
        }
        return hasMatches
            ? ("magnifyingglass", "No results", "Nothing matches \u{201C}\(search)\u{201D}.")
            : ("magnifyingglass", "No matches in the feed", "Check back soon.")
    }

    private var sections: [(title: String, matches: [Match])] {
        Self.sections(store.matches, search: search, favourite: store.hasFavourite)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SearchField(prompt: "Search teams or series", text: $search, focused: $searchFocused)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1, pinnedViews: []) {
                    if sections.isEmpty {
                        let empty = Self.emptyState(hasMatches: !store.matches.isEmpty, loaded: store.lastUpdated != nil,
                                                    error: store.error, search: search)
                        EmptyStateView(symbol: empty.symbol, title: empty.title, message: empty.message, tint: Theme.meta)
                    }
                    ForEach(sections, id: \.title) { section in
                        SectionLabel(title: section.title, first: section.title == sections.first?.title)
                        ForEach(section.matches) { match in
                            PickerRow(match: match, selected: store.isWatched(match)) {
                                store.toggle(match)
                            }
                        }
                    }
                }
                .padding(.bottom, 18) // last row can scroll clear of the fade
            }
            .frame(height: min(320, maxHeight))
            // Fade at the bottom so a cut-off row reads as "more below".
            .bottomFade(true)
        }
        .onAppear { searchFocused = true }
    }
}

struct PickerRow: View {
    let match: Match
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 1) {
                    // One team per line so every row has the same shape.
                    Group {
                        if match.sides.count == 2 {
                            ForEach(match.sides, id: \.self) { Text($0.name).lineLimit(1) }
                        } else {
                            Text(match.title).lineLimit(2)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    Text([match.detail, match.league].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: Theme.metaSize))
                        .foregroundStyle(Theme.meta)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                .help(match.fullDescription)
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.meta))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PickerRowStyle(selected: selected))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([match.title, match.detail, match.league].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PickerRowStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        HoverPlate(pressed: configuration.isPressed, selected: selected, radius: 8) {
            configuration.label
        }
    }
}

// MARK: - Live detail

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }
}

// Tap to show or hide the current batters and bowlers with their figures.
struct PlayersSection: View {
    let detail: LiveDetail
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Text("Batters & bowlers")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .foregroundStyle(Theme.meta)
                .padding(.horizontal, 6)
                .frame(height: 26)
            }
            .buttonStyle(PlainHoverStyle())
            // Faint resting fill so it reads as a button, not a caption. Sits under the hover fill.
            .background(open ? Color.clear : Theme.band.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, -6)
            .accessibilityLabel(open ? "Hide batters and bowlers" : "Show batters and bowlers")
            .help(open ? "Hide batters and bowlers" : "Show batters and bowlers")
            if open {
                PlayersTable(batters: detail.batters, bowlers: detail.bowlers)
                    .padding(.horizontal, -6) // text lines up with the card's other text
            }
        }
    }
}

struct PlainHoverStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverPlate(pressed: configuration.isPressed, radius: 6) { configuration.label }
    }
}

// BATTING        R    B   4s  6s     SR
// Mahfijul Islam*  30   80    4   1   37.5
// BOWLING        O    M    R   W   ECON
// Kagiso Rabada    7    5   10   1   1.42
struct PlayersTable: View {
    let batters: [BatterLine]
    let bowlers: [BowlerLine]

    // Fixed number columns so both halves line up. Numbers are right-aligned, so the
    // gap before a column is its width minus its text: 3-digit balls and bowler runs
    // ("102 111", "3 112") need 30 and 27 to stay apart.
    private static let widths: [CGFloat] = [28, 30, 27, 20, 46]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !batters.isEmpty {
                header("Batting", ["R", "B", "4s", "6s", "SR"])
                ForEach(batters, id: \.id) { b in
                    row(name: b.name, short: b.shortName, mark: b.onStrike, cells: Self.cells(b))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.spoken(b))
                }
            }
            if !bowlers.isEmpty {
                header("Bowling", ["O", "M", "R", "W", "ECON"])
                    .padding(.top, batters.isEmpty ? 0 : 6)
                ForEach(bowlers, id: \.id) { b in
                    row(name: b.name, short: b.shortName, mark: false, cells: Self.cells(b))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.spoken(b))
                }
            }
        }
        .monospacedDigit()
    }

    // One number column: its text and whether it's the headline figure (bold).
    struct Cell: Equatable {
        let text: String
        let bold: Bool
        init(_ text: String, bold: Bool = false) { self.text = text; self.bold = bold }
    }

    // R B 4s 6s SR, runs in bold.
    static func cells(_ b: BatterLine) -> [Cell] {
        [Cell("\(b.runs)", bold: true), Cell("\(b.balls)"), Cell("\(b.fours)"), Cell("\(b.sixes)"), Cell(b.strikeRate)]
    }

    // O M R W ECON, wickets in bold.
    static func cells(_ b: BowlerLine) -> [Cell] {
        [Cell(b.overs), Cell("\(b.maidens)"), Cell("\(b.conceded)"), Cell("\(b.wickets)", bold: true), Cell(b.economy)]
    }

    // VoiceOver reads a row as a sentence. No rate until a ball has been faced or bowled.
    static func spoken(_ b: BatterLine) -> String {
        "\(b.name)\(b.onStrike ? ", on strike" : ""), \(b.runs) off \(b.balls) balls, \(b.fours) fours, \(b.sixes) sixes"
            + (b.balls > 0 ? ", strike rate \(b.strikeRate)" : "")
    }

    static func spoken(_ b: BowlerLine) -> String {
        "\(b.name), \(b.oversSpoken), \(b.maidens) maidens, \(b.conceded) runs, \(b.wickets) wickets"
            + (b.balls > 0 ? ", economy \(b.economy)" : "")
    }

    private func header(_ title: String, _ cols: [String]) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .textCase(.uppercase)
                .kerning(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(cols.enumerated()), id: \.offset) { i, c in
                Text(c).frame(width: Self.widths[i], alignment: .trailing)
            }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Theme.meta)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(Theme.band, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityHidden(true)
    }

    private func row(name: String, short: String, mark: Bool, cells: [Cell]) -> some View {
        HStack(spacing: 0) {
            // Full name if it fits, else "M Islam", else the feed's short name ("Shanto").
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    Text(name)
                    Text(initialled(name))
                    // Feed short name only when it really is shorter ("Shanto"); it's often empty or the full name.
                    Text(shortest(name, short: short)).truncationMode(.tail)
                }
                .lineLimit(1)
                // Always there, so a name doesn't jump between full and short as strike changes.
                Text("*").opacity(mark ? 1 : 0).accessibilityHidden(true)
            }
            .font(.system(size: Theme.bodySize))
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(name)
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                Text(cell.text)
                    .font(.system(size: Theme.bodySize, weight: cell.bold ? .semibold : .regular))
                    .foregroundStyle(cell.bold ? Color.primary : Theme.meta)
                    .lineLimit(1)
                    .frame(width: Self.widths[i], alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
    }

    func initialled(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count > 1, let first = parts.first?.first else { return name }
        return "\(first) " + parts.dropFirst().joined(separator: " ")
    }

    // Last resort when even "M Islam" won't fit.
    func shortest(_ name: String, short: String) -> String {
        !short.isEmpty && short.count < initialled(name).count ? short : initialled(name)
    }
}

// "CRR 5.14   RRR 11.47   Last 5 ov 38/2 (7.60)"
struct RatesRow: View {
    let rates: [(label: String, value: String)]

    var body: some View {
        // Drop rates from the end (Last 5 ov first) rather than spill past the card.
        ViewThatFits(in: .horizontal) {
            ForEach((1...max(rates.count, 1)).reversed(), id: \.self) { n in
                row(Array(rates.prefix(n)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rates.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }

    private func row(_ shown: [(label: String, value: String)]) -> some View {
        HStack(spacing: 12) {
            ForEach(shown, id: \.label) { rate in
                HStack(spacing: 4) {
                    Text(rate.label)
                        .font(.system(size: Theme.metaSize))
                        .foregroundStyle(Theme.meta)
                    Text(rate.value)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .fixedSize()
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }
}

// Every over on one line, newest first, packed tight. The current over sits at the left edge.
// Inside each over the newest ball comes straight after the over number, so
// older balls get pushed right. Older overs follow straight after, then scroll off right.
// Trackpad users can swipe sideways.
// Mouse users: click the line, then the scroll wheel moves it left/right.
struct OversLine: View {
    let overs: [OverSummary]
    @StateObject private var scroll = OversLineScroll()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Each over is only as wide as its balls, so the current over
                    // grows ball by ball (extras included) with no gap after it.
                    ForEach(Array(overs.reversed()), id: \.number) { over in
                        let isCurrent = over.number == overs.last?.number
                        OverGroup(over: over)
                            .padding(.leading, 12)
                            .padding(.trailing, 12)
                            .overlay(alignment: .leading) {
                                if !isCurrent {
                                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 30)
                                }
                            }
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollDisabled(false) // the card list may disable scrolling; don't inherit that
            .defaultScrollAnchor(.leading)
            .mask {
                // Fade on the right so older overs read as "more this way".
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(scroll.engaged ? 0.6 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { scroll.tap() }
            .onHover { scroll.hover($0) }
            .onChange(of: lastBallKey) { _, _ in
                // New ball: jump to it, unless the user is busy looking back.
                guard !scroll.engaged else { return }
                guard let n = overs.last?.number else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(n, anchor: .leading) }
            }
            .onAppear { scroll.wheel.start() }
            .onDisappear { scroll.wheel.stop() }
            .help(scroll.engaged ? "Scroll to see earlier overs. Click again to stop." : "Click, then scroll to see earlier overs")
        }
    }

    private var lastBallKey: String {
        guard let last = overs.last else { return "" }
        return "\(last.number)-\(last.balls.count)"
    }
}

// Click-to-scroll state for the overs line. A click engages it, a second click
// or the pointer leaving disengages it. The wheel is redirected only while
// engaged and hovered.
final class OversLineScroll: ObservableObject {
    @Published private(set) var engaged = false
    let wheel = WheelRedirect()

    func tap() {
        engaged.toggle()
        wheel.active = engaged
    }

    func hover(_ inside: Bool) {
        wheel.hovering = inside
        if !inside {
            engaged = false
            wheel.active = false
        }
    }
}

// Turns up/down mouse-wheel scrolls into left/right while the line is clicked
// and the pointer is over it. Without this a normal mouse can't scroll sideways.
final class WheelRedirect {
    var active = false
    var hovering = false
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.active, self.hovering,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  let cg = event.cgEvent?.copy() else { return event }
            let pairs: [(CGEventField, CGEventField)] = [
                (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
                (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
                (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
            ]
            for (vertical, horizontal) in pairs {
                if vertical == .scrollWheelEventFixedPtDeltaAxis1 {
                    cg.setDoubleValueField(horizontal, value: cg.getDoubleValueField(vertical))
                    cg.setDoubleValueField(vertical, value: 0)
                } else {
                    cg.setIntegerValueField(horizontal, value: cg.getIntegerValueField(vertical))
                    cg.setIntegerValueField(vertical, value: 0)
                }
            }
            guard let redirected = NSEvent(cgEvent: cg) else { return event }
            return redirected
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}

// One over inside the line: "40th  6/RUNS [•][W][•][•][1][4]"
// The run total sits stacked above a small "RUNS" label, like Cricinfo.
struct OverGroup: View {
    let over: OverSummary

    var body: some View {
        HStack(spacing: 4) {
            Text(ordinal(over.number))
                .font(.system(size: Theme.metaSize, weight: .medium))
                .foregroundStyle(Theme.meta)
                .monospacedDigit()
                .fixedSize()
                .padding(.trailing, 4)
            VStack(spacing: 0) {
                Text("\(over.runs)")
                    .font(.system(size: Theme.bodySize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(runsCaption)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.meta)
            }
            .fixedSize()
            .frame(minWidth: 26)
            .padding(.trailing, 2)
            // Newest ball first, right after the run total.
            ForEach(Array(over.balls.enumerated().reversed()), id: \.offset) { _, ball in
                BallChip(ball: ball)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // Under the run total: "RUN" for exactly one, else "RUNS".
    var runsCaption: String { over.runs == 1 ? "RUN" : "RUNS" }

    // "40th over, 6 runs: dot, wicket, ..." oldest ball first.
    var spoken: String {
        "\(ordinal(over.number)) over, \(over.runs == 1 ? "1 run" : "\(over.runs) runs"): " + over.balls.map(\.spoken).joined(separator: ", ")
    }

    func ordinal(_ n: Int) -> String {
        let tens = n % 100
        let suffix = (11...13).contains(tens) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return "\(n)\(suffix)"
    }
}

struct BallChip: View {
    let ball: Ball

    var body: some View {
        Text(ball.label)
            .font(.system(size: ball.label.count > 2 ? 9 : 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(fg)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, ball.label.count > 2 ? 3.5 : 0)
            .frame(minWidth: 20, minHeight: 20)
            .background(bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                if ball.kind == .dot || ball.kind == .runs {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                }
            }
    }

    private var bg: Color {
        switch ball.kind {
        case .four: Theme.four
        case .six: Theme.six
        case .wicket: Theme.wicket
        case .extra: Theme.paused.opacity(0.15)
        case .dot, .runs: Color.primary.opacity(0.07)
        }
    }

    private var fg: Color {
        switch ball.kind {
        case .four, .six, .wicket: .white
        case .extra: Theme.pausedInk
        case .dot: Theme.meta
        case .runs: .primary
        }
    }
}

extension View {
    // Fades the bottom 18pt out when `on`. Always the same view, so toggling it
    // doesn't rebuild what's inside (scroll spot, live dot, overs line state).
    func bottomFade(_ on: Bool) -> some View {
        mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(on ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
            }
        }
    }
}
