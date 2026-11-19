import Foundation
import UserNotifications

// Alerts for favourite teams' matches: wickets, every 100 team runs, batters
// reaching 50 and 100, and the result. Plain code, so tests can drive it.

// One innings as the score text shows it: "245/6" or "137" (all out).
struct InningsScore: Hashable {
    let runs: Int
    let wickets: Int
}

// "98 & 309/9 (93 ov)" -> [98/10, 309/9]. "" -> []. Anything odd -> nil.
// Declared ("450/8d") reads as 8 down.
func parseInnings(_ score: String) -> [InningsScore]? {
    let trimmed = score.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return [] }
    var out: [InningsScore] = []
    for part in trimmed.components(separatedBy: "&") {
        // Drop the "(25 ov, target 97)" bit.
        let bare = part.split(separator: "(", maxSplits: 1).first.map(String.init) ?? ""
        // Keep digits and the slash, so "450/8d" and "450/8 dec" read as 450/8.
        let text = String(bare.filter { $0.isASCII && ($0.isNumber || $0 == "/") })
        let bits = text.split(separator: "/", omittingEmptySubsequences: false)
        guard let runs = bits.first.flatMap({ Int($0) }) else { return nil }
        switch bits.count {
        case 1: out.append(InningsScore(runs: runs, wickets: 10))
        case 2:
            guard let w = Int(bits[1]), (0...10).contains(w) else { return nil }
            out.append(InningsScore(runs: runs, wickets: w))
        default: return nil
        }
    }
    return out
}

struct MilestoneAlert: Equatable {
    let matchID: String
    let title: String
    let body: String
}

// Remembers what has been reached, so each milestone fires once. A match or
// batter seen for the first time only sets the starting point: launching the
// app mid-match must not fire everything that already happened.
struct MilestoneTracker {
    private(set) var reached: Set<String> = []
    private var seenMatches: Set<String> = []
    private var seenDetails: Set<String> = []   // "match/innings"
    private var states: [String: String] = [:]

    // Call once per refresh with every match in the feed. `alertFor` says which
    // matches may alert (favourite, not stopped, setting on). The rest are
    // still tracked, so turning alerts on later doesn't fire old news.
    mutating func update(matches: [Match], details: [String: LiveDetail], alertFor: (Match) -> Bool) -> [MilestoneAlert] {
        var alerts: [MilestoneAlert] = []
        for match in matches {
            var lines: [String] = []
            let firstSight = seenMatches.insert(match.id).inserted

            for side in match.sides where !side.id.isEmpty {
                guard let innings = parseInnings(side.score) else { continue }
                for (i, inn) in innings.enumerated() {
                    let key = "\(match.id)/\(side.id)/\(i)"
                    let newWickets = inn.wickets > 0 ? (1...inn.wickets).filter { reach("\(key)/w\($0)") } : []
                    let newHundreds = inn.runs >= 100 ? (1...inn.runs / 100).filter { reach("\(key)/r\($0)") } : []
                    guard !firstSight else { continue }
                    let name = side.name
                    if inn.wickets == 10 && newWickets.contains(10) {
                        lines.append("\(name) all out for \(inn.runs)")
                    } else if !newWickets.isEmpty {
                        let what = newWickets.count == 1 ? "Wicket" : "\(newWickets.count) wickets"
                        lines.append("\(what): \(name) \(inn.runs)/\(inn.wickets)")
                    } else if let top = newHundreds.max() {
                        lines.append("\(name) pass \(top * 100): \(inn.runs)/\(inn.wickets)")
                    }
                }
            }

            if let d = details[match.id] {
                let dKey = "\(match.id)/\(d.period)"
                let firstDetail = seenDetails.insert(dKey).inserted
                for b in d.batters {
                    let marks = [50, 100, 150, 200, 250, 300].filter { b.runs >= $0 && reach("\(dKey)/\(b.id)/\($0)") }
                    if !firstSight, !firstDetail, let top = marks.max() {
                        let team = d.battingTeam.map { " (\($0))" } ?? ""
                        lines.append("\(b.name)\(team) reaches \(top)")
                    }
                }
            }

            let before = states.updateValue(match.state, forKey: match.id)
            if before == "in", match.state == "post", !match.summary.isEmpty {
                lines.append(match.summary)
            }

            if !lines.isEmpty, alertFor(match) {
                alerts.append(MilestoneAlert(matchID: match.id, title: match.title, body: lines.joined(separator: ". ")))
            }
        }
        return alerts
    }

    // True the first time a milestone is seen.
    private mutating func reach(_ key: String) -> Bool { reached.insert(key).inserted }
}

// MARK: - Sending

@MainActor
protocol MilestoneNotifier: AnyObject {
    func requestPermission()
    func send(_ alert: MilestoneAlert)
}

// Used by tests and by `swift test`'s bare process, where there's no app bundle.
final class SilentNotifier: MilestoneNotifier {
    func requestPermission() {}
    func send(_ alert: MilestoneAlert) {}
}

// macOS notifications. Needs a real app bundle: UNUserNotificationCenter
// crashes without one, so the app only makes this when it has a bundle ID.
final class SystemNotifier: NSObject, MilestoneNotifier, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var asked = false

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() {
        guard !asked else { return }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(_ alert: MilestoneAlert) {
        requestPermission()
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "milestone-\(alert.matchID)-\(UUID().uuidString)", content: content, trigger: nil)
        center.add(request)
    }

    // Show banners even while the panel is the active window.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    static func makeIfBundled() -> MilestoneNotifier {
        Bundle.main.bundleIdentifier == nil ? SilentNotifier() : SystemNotifier()
    }
}
