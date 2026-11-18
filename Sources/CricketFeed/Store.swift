import Foundation
import SwiftUI

@MainActor
final class ScoreStore: ObservableObject {
    @Published var matches: [Match] = []
    @Published var lastUpdated: Date?
    @Published var error: String?
    @Published var watched: Set<String> {
        didSet { UserDefaults.standard.set(Array(watched), forKey: Self.watchedKey) }
    }

    static let watchedKey = "watchedMatchIDs"
    let refreshSeconds: UInt64 = 10

    private var loop: Task<Void, Never>?

    init() {
        watched = Set(UserDefaults.standard.stringArray(forKey: Self.watchedKey) ?? [])
    }

    var watchedMatches: [Match] {
        matches.filter { watched.contains($0.id) }
    }

    func toggle(_ match: Match) {
        if watched.contains(match.id) { watched.remove(match.id) } else { watched.insert(match.id) }
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: (self?.refreshSeconds ?? 10) * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        do {
            let fresh = try await fetchMatches()
            matches = fresh
            lastUpdated = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
