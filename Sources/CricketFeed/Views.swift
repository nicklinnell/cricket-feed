import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: ScoreStore
    var onSizeChange: (CGSize) -> Void = { _ in }
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if picking {
                MatchPicker(store: store)
            } else {
                watchedList
            }
            footer
        }
        .padding(10)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
    }

    private var header: some View {
        HStack {
            Text(picking ? "Pick matches" : "Cricket")
                .font(.headline)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: { Image(systemName: "arrow.clockwise") }
            .help("Refresh now")
            Button {
                picking.toggle()
            } label: { Image(systemName: picking ? "checkmark" : "plus") }
            .help(picking ? "Done" : "Pick matches")
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var watchedList: some View {
        let items = store.watchedMatches
        if items.isEmpty {
            Text(store.watched.isEmpty
                 ? "No matches picked. Press + to choose some."
                 : "Your picked matches are not in the feed right now.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(items) { match in
                MatchCard(match: match)
                    .contextMenu {
                        Button("Open on Cricinfo") { NSWorkspace.shared.open(match.cricinfoURL) }
                        Button("Stop watching") { store.toggle(match) }
                    }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let err = store.error {
                Text(err).foregroundStyle(.red)
            } else if let t = store.lastUpdated {
                Text("Updated \(t.formatted(date: .omitted, time: .standard))")
            } else {
                Text("Loading...")
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct MatchCard: View {
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if match.isLive {
                    Circle().fill(.red).frame(width: 7, height: 7)
                }
                Text(match.league)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(match.stateLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(match.sides, id: \.self) { side in
                HStack {
                    Text(side.name).lineLimit(1)
                    Spacer()
                    Text(side.score).monospacedDigit().bold()
                }
                .font(.callout)
            }
            if !match.summary.isEmpty {
                Text(match.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MatchPicker: View {
    @ObservedObject var store: ScoreStore
    @State private var search = ""

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search teams or series", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filtered) { match in
                        Toggle(isOn: Binding(
                            get: { store.watched.contains(match.id) },
                            set: { _ in store.toggle(match) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(match.title).font(.callout)
                                Text("\(match.stateLabel)  |  \(match.league)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(height: 320)
        }
    }
}
