import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: ScoreStore
    @ObservedObject var room: PanelRoom
    var onSizeChange: (CGSize) -> Void = { _ in }
    @State private var picking = false
    @State private var refreshing = false
    @State private var spin = 0.0
    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if picking {
                MatchPicker(store: store)
            } else {
                watchedList
            }
            footer
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
            Text(picking ? "Pick matches" : "Cricket")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            if picking {
                Button("Done") { picking = false }
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
                    picking = true
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
        withAnimation(.linear(duration: 0.6)) { spin += 360 }
        await store.refresh()
        refreshing = false
    }

    @ViewBuilder
    private var watchedList: some View {
        let items = store.watchedMatches
        if store.watched.isEmpty {
            EmptyStateView(
                symbol: "figure.cricket",
                title: "No matches yet",
                message: "Pick the games you want to follow and their scores will show here.",
                action: ("Pick matches", { picking = true })
            )
        } else if store.lastUpdated == nil && store.error == nil {
            ForEach(0..<min(store.watched.count, 2), id: \.self) { _ in SkeletonCard() }
        } else if items.isEmpty {
            EmptyStateView(
                symbol: store.lastUpdated == nil ? "wifi.slash" : "calendar.badge.clock",
                title: store.lastUpdated == nil ? "Can't reach the score feed" : "Nothing on right now",
                message: store.lastUpdated == nil
                    ? "Will keep trying every few seconds."
                    : "Your picked matches aren't in the feed at the moment.",
                action: store.lastUpdated == nil ? nil : ("Pick matches", { picking = true })
            )
        } else {
            // Scrolls only once the cards would be taller than the screen allows.
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(items) { match in
                        MatchCard(match: match)
                            .contextMenu {
                                Button("Open on Cricinfo") { NSWorkspace.shared.open(match.cricinfoURL) }
                                Button("Stop watching") { store.toggle(match) }
                            }
                    }
                }
                .padding(.bottom, scrolls ? 6 : 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollDisabled(!scrolls)
            .frame(height: min(max(listHeight, 1), room.maxListHeight))
            // Soft fade at the bottom so a cut-off card reads as "more below".
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(scrolls ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 18)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let err = store.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.paused)
                Text(store.lastUpdated.map { "Offline · last update \(short($0))" } ?? "Offline")
                    .help(err)
                    .accessibilityHint(err)
            } else if let t = store.lastUpdated {
                Text("Updated \(short(t))")
            } else {
                ProgressView().controlSize(.mini)
                Text("Fetching scores")
            }
            Spacer()
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 2)
    }

    private var scrolls: Bool { listHeight > room.maxListHeight }

    private func short(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}

struct MatchCard: View {
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .center, spacing: 6) {
                    Text(match.detail.isEmpty ? match.league : match.detail)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    StatusPill(match: match)
                }
                if !match.detail.isEmpty {
                    Text(match.league)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 2)
            ForEach(match.sides, id: \.self) { side in
                SideRow(side: side, batting: battingSide == side)
            }
            if !match.summary.isEmpty {
                Text(match.summary)
                    .font(.system(size: 11.5, weight: inPlay ? .medium : .regular))
                    .foregroundStyle(inPlay ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                    }
            }
        }
        .padding(10)
        .cardBackground()
    }

    // Emphasise the summary only for live play, and not for stale toss news.
    private var inPlay: Bool {
        MatchPhase(match) == .live && !match.summary.localizedCaseInsensitiveContains("won toss")
    }

    // Best guess: in live play, the only side whose score has overs in brackets is batting.
    private var battingSide: Match.Side? {
        guard MatchPhase(match) == .live else { return nil }
        let withOvers = match.sides.filter { !ScoreParts($0.score).detail.isEmpty }
        return withOvers.count == 1 ? withOvers[0] : nil
    }
}

struct MatchPicker: View {
    @ObservedObject var store: ScoreStore
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [Match] {
        let all = store.matches.sorted { a, b in
            // Live first, then upcoming, then finished.
            rank(a) == rank(b) ? a.title < b.title : rank(a) < rank(b)
        }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.league.localizedCaseInsensitiveContains(search)
        }
    }

    private func rank(_ m: Match) -> Int {
        switch m.state { case "in": 0; case "pre": 1; default: 2 }
    }

    private var sections: [(title: String, matches: [Match])] {
        let groups = Dictionary(grouping: filtered, by: rank)
        return [(0, "Live"), (1, "Upcoming"), (2, "Finished")].compactMap { key, title in
            guard let m = groups[key], !m.isEmpty else { return nil }
            return (title, m)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1, pinnedViews: []) {
                    if sections.isEmpty {
                        if store.matches.isEmpty && store.lastUpdated == nil {
                            EmptyStateView(
                                symbol: store.error == nil ? "hourglass" : "wifi.slash",
                                title: store.error == nil ? "Fetching matches" : "Can't reach the score feed",
                                message: store.error == nil ? "One moment." : "Will keep trying every few seconds."
                            )
                        } else {
                            EmptyStateView(
                                symbol: "magnifyingglass",
                                title: store.matches.isEmpty ? "No matches in the feed" : "No results",
                                message: store.matches.isEmpty
                                    ? "Check back soon."
                                    : "Nothing matches \u{201C}\(search)\u{201D}."
                            )
                        }
                    }
                    ForEach(sections, id: \.title) { section in
                        Text(section.title)
                            .font(.system(size: 9.5, weight: .bold))
                            .textCase(.uppercase)
                            .kerning(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, section.title == sections.first?.title ? 2 : 10)
                            .padding(.bottom, 3)
                        ForEach(section.matches) { match in
                            PickerRow(match: match, selected: store.watched.contains(match.id)) {
                                store.toggle(match)
                            }
                        }
                    }
                }
            }
            .frame(height: 320)
        }
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search teams or series", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                    Text(match.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text([match.detail, match.league].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PickerRowStyle(selected: selected))
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
