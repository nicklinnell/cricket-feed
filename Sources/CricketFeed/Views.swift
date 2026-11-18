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
                MatchPicker(store: store, maxHeight: room.maxListHeight - 34)
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
                        MatchCard(match: match, detail: store.details[match.id])
                            .contextMenu {
                                Button("Open on Cricinfo") { NSWorkspace.shared.open(match.cricinfoURL) }
                                Button("Stop watching") { store.toggle(match) }
                            }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                .padding(.bottom, scrolls ? 18 : 0)
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
    var detail: LiveDetail?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .center, spacing: 6) {
                    Text(match.detail.isEmpty ? match.league : match.detail + dayNight)
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
                if !venue.isEmpty {
                    Text(venue)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 2)
            ForEach(match.sides, id: \.self) { side in
                SideRow(side: side, batting: battingSide == side)
            }
            if !summaryText.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summaryText)
                        .font(.system(size: 11.5, weight: inPlay ? .medium : .regular))
                        .foregroundStyle(inPlay ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let live = liveDetail, !live.rates.isEmpty {
                        RatesRow(rates: live.rates)
                    }
                }
                .padding(.top, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Hairline() }
            }
            if let overs = liveDetail?.overs, !overs.isEmpty {
                OversLine(overs: overs)
                    .padding(.top, 6)
                .overlay(alignment: .top) { Hairline() }
            }
        }
        .padding(10)
        .cardBackground()
    }

    // Ball-by-ball extras only while the match is in play (live or a break).
    private var liveDetail: LiveDetail? {
        match.isLive ? detail : nil
    }

    // "Australia need 126 runs in 63 balls." beats the feed's shorter summary.
    private var summaryText: String {
        liveDetail?.chase ?? match.summary
    }

    // "3rd ODI (D/N), England tour of Australia at Hobart, Nov 18 2026"
    //  -> dayNight " (D/N)", venue "Hobart, Nov 18 2026".
    private var dayNight: String {
        let full = match.fullDescription
        guard full.hasPrefix(match.detail) else { return "" }
        let rest = full.dropFirst(match.detail.count)
        guard rest.hasPrefix(" ("), let close = rest.firstIndex(of: ")") else { return "" }
        return String(rest[...close])
    }

    private var venue: String {
        guard let r = match.fullDescription.range(of: " at ", options: .backwards) else { return "" }
        return String(match.fullDescription[r.upperBound...])
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
    var maxHeight: CGFloat = 320
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
            .frame(height: min(320, maxHeight))
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

// MARK: - Live detail

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
    }
}

// "CRR 5.14   RRR 11.47   Last 5 ov 38/2 (7.60)"
struct RatesRow: View {
    let rates: [(label: String, value: String)]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(rates, id: \.label) { rate in
                HStack(spacing: 3) {
                    Text(rate.label).foregroundStyle(.secondary)
                    Text(rate.value).fontWeight(.medium)
                }
                .fixedSize()
            }
        }
        .font(.system(size: 10.5))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }
}

// Every over on one line. The current over starts at the left edge and its
// balls build towards the right. Older overs sit off-screen to the left.
// Trackpad users can swipe sideways.
// Mouse users: click the line, then the scroll wheel moves it left/right.
struct OversLine: View {
    let overs: [OverSummary]
    @State private var engaged = false
    @State private var wheel = WheelRedirect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(overs, id: \.number) { over in
                        if over.number == overs.last?.number {
                            // Current over fills the visible width, left-aligned,
                            // so new balls appear left and grow rightwards.
                            OverGroup(over: over)
                                .padding(.leading, 12)
                                .containerRelativeFrame(.horizontal, alignment: .leading)
                        } else {
                            OverGroup(over: over)
                                .padding(.leading, 8)
                                .padding(.trailing, 8)
                                .overlay(alignment: .trailing) {
                                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5, height: 14)
                                }
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollDisabled(false) // the card list may disable scrolling; don't inherit that
            .defaultScrollAnchor(.trailing)
            .mask {
                // Fade on the left so older overs read as "more this way".
                // The current over is inset 12pt so the fade doesn't cover it.
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                    Rectangle()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(engaged ? 0.6 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { engaged.toggle() }
            .onHover { inside in
                wheel.hovering = inside
                if !inside { engaged = false }
            }
            .onChange(of: engaged) { _, on in wheel.active = on }
            .onChange(of: lastBallKey) { _, _ in
                // New ball: jump to it, unless the user is busy looking back.
                guard !engaged else { return }
                guard let n = overs.last?.number else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(n, anchor: .trailing) }
            }
            .onAppear { wheel.start() }
            .onDisappear { wheel.stop() }
            .help(engaged ? "Scroll to see earlier overs. Click again to stop." : "Click, then scroll to see earlier overs")
        }
    }

    private var lastBallKey: String {
        guard let last = overs.last else { return "" }
        return "\(last.number)-\(last.balls.count)"
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
            return NSEvent(cgEvent: cg) ?? event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}

// One over inside the line: "40th [•][W][•][•][1][•] 1"
struct OverGroup: View {
    let over: OverSummary

    var body: some View {
        HStack(spacing: 3) {
            Text(ordinal(over.number))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
                .padding(.trailing, 2)
            ForEach(Array(over.balls.enumerated()), id: \.offset) { _, ball in
                BallChip(ball: ball)
            }
            Text("\(over.runs)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
                .padding(.leading, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ordinal(over.number)) over, \(over.runs == 1 ? "1 run" : "\(over.runs) runs"): " + over.balls.map(\.spoken).joined(separator: ", "))
    }

    private func ordinal(_ n: Int) -> String {
        let tens = n % 100
        let suffix = (11...13).contains(tens) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return "\(n)\(suffix)"
    }
}

struct BallChip: View {
    let ball: Ball

    var body: some View {
        Text(ball.label)
            .font(.system(size: ball.label.count > 2 ? 8.5 : 10.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(fg)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, ball.label.count > 2 ? 2.5 : 0)
            .frame(minWidth: 18, minHeight: 18)
            .background(bg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var bg: Color {
        switch ball.kind {
        case .four: Theme.four
        case .six: Theme.six
        case .wicket: Theme.live
        case .extra: Theme.paused.opacity(0.15)
        case .dot, .runs: Color.primary.opacity(0.07)
        }
    }

    private var fg: Color {
        switch ball.kind {
        case .four, .six, .wicket: .white
        case .extra: Theme.paused
        case .dot: .secondary
        case .runs: .primary
        }
    }
}
