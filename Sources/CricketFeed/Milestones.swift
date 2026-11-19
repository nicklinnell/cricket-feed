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
        // "450/8d" and "450/8 dec" read as 450/8. Anything else besides digits and one slash is odd.
        var text = bare.trimmingCharacters(in: .whitespaces).lowercased()
        for suffix in [" dec", "dec", "d"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
            break
        }
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "/") }) else { return nil }
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
    // Ball-by-ball keys ("match/innings") with a starting point. Dropped when
    // the user stops following the match, so coming back doesn't fire what
    // happened meanwhile. A feed blip or the match ending keeps them.
    private var trackedDetails: Set<String> = []
    private var seenLive: Set<String> = []

    // Call once per refresh with every match in the feed. `alertFor` says which
    // matches may alert (favourite, not stopped, setting on). The rest are
    // still tracked, so turning alerts on later doesn't fire old news.
    // `following` says which matches are in the panel (and so get ball-by-ball).
    mutating func update(matches: [Match], details: [String: LiveDetail],
                         following: (Match) -> Bool = { _ in true }, alertFor: (Match) -> Bool) -> [MilestoneAlert] {
        var alerts: [MilestoneAlert] = []
        for match in matches where details[match.id] == nil && !following(match) {
            trackedDetails = trackedDetails.filter { !$0.hasPrefix(match.id + "/") }
        }
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
                    if let top = newHundreds.max() {
                        lines.append("\(name) pass \(top * 100)")
                    }
                    if inn.wickets == 10 && newWickets.contains(10) {
                        lines.append("\(name) all out for \(inn.runs)")
                    } else if !newWickets.isEmpty {
                        let what = newWickets.count == 1 ? "Wicket" : "\(newWickets.count) wickets"
                        lines.append("\(what): \(name) \(inn.runs)/\(inn.wickets)")
                    } else if !newHundreds.isEmpty {
                        lines[lines.count - 1] += ": \(inn.runs)/\(inn.wickets)"
                    }
                }
            }

            if let d = details[match.id] {
                let dKey = "\(match.id)/\(d.period)"
                let firstDetail = trackedDetails.insert(dKey).inserted
                for b in d.inningsBatters {
                    let marks = stride(from: 50, through: b.runs, by: 50).filter { reach("\(dKey)/\(b.id)/\($0)") }
                    if !firstDetail, let top = marks.max() {
                        let team = d.battingTeam.map { " (\($0))" } ?? ""
                        lines.append("\(b.name)\(team) reaches \(top)")
                    }
                }
            }

            // Result: once, and only for a match we saw being played.
            if match.state == "in" { seenLive.insert(match.id) }
            if match.state == "post", seenLive.contains(match.id), !match.summary.isEmpty, reach("\(match.id)/result") {
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
// crashes without one, so the app only makes this inside a .app.
final class SystemNotifier: NSObject, MilestoneNotifier, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    // Shows the prompt the first time; after that it answers straight away.
    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Adds the notification only once permission is answered, so the first
    // alert isn't dropped while the prompt is still up.
    func send(_ alert: MilestoneAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "milestone-\(alert.matchID)-\(UUID().uuidString)", content: content, trigger: nil)
        let center = center
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { center.add(request) }
        }
    }

    // Show banners even while the panel is the active window.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Only inside a real .app: test runners have a bundle ID but no app bundle.
    static func makeIfBundled(_ bundle: Bundle = .main) -> MilestoneNotifier {
        bundle.bundleURL.pathExtension == "app" ? SystemNotifier() : SilentNotifier()
    }
}
