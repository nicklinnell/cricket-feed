import Foundation

// Ball-by-ball data from ESPN's (unofficial) play-by-play feed.

struct PBPResponse: Decodable {
    let commentary: PBPPage
}

struct PBPPage: Decodable {
    let pageCount: Int
    let items: [PBPItem]
}

struct PBPItem: Decodable {
    let scoreValue: Int?
    let playType: PBPType?
    let over: PBPOver?
    let innings: PBPInnings?
    let dismissal: PBPDismissal?
    let team: Team?
    let shortText: String?
    let batsman: PBPBatter?
    let otherBatsman: PBPBatter?
    let bowler: PBPBowler?
    let otherBowler: PBPBowler?
}

struct PBPAthlete: Decodable {
    let id: String?
    let displayName: String?
    let shortName: String?    // "Rabada"; often empty
}

struct PBPPerson: Decodable { let athlete: PBPAthlete? }

// Figures are totals after this ball.
struct PBPBatter: Decodable {
    let athlete: PBPAthlete?
    let totalRuns: Int?
    let faced: Int?
    let fours: Int?
    let sixes: Int?
}

struct PBPBowler: Decodable {
    let athlete: PBPAthlete?
    let balls: Int?
    let maidens: Int?
    let conceded: Int?
    let wickets: Int?
}

struct PBPType: Decodable { let description: String? }

struct PBPOver: Decodable {
    let number: Int?
    let overs: Double?
    let wide: Int?
    let noBall: Int?
    let legByes: Int?
    let byes: Int?
    let complete: Bool?
}

struct PBPInnings: Decodable {
    let runRate: Double?
    let requiredRunRate: Double?
    let remainingBalls: Int?
    let remainingRuns: Int?
    let target: Int?
    let ballLimit: Int?
}

struct PBPDismissal: Decodable {
    let dismissal: Bool?
    let batsman: PBPPerson?   // who is out (can be the non-striker)
}

// MARK: - What the UI shows

struct Ball: Hashable {
    enum Kind { case dot, runs, four, six, wicket, extra }
    let label: String
    let kind: Kind
    let runs: Int

    var spoken: String {
        switch kind {
        case .dot: "dot"
        case .wicket: "wicket"
        case .four: "four"
        case .six: "six"
        case .runs: runs == 1 ? "1 run" : "\(runs) runs"
        case .extra: label
        }
    }
}

struct OverSummary: Hashable {
    let number: Int      // 1-based, e.g. 38 = "38th over"
    let balls: [Ball]
    var runs: Int { balls.reduce(0) { $0 + $1.runs } }
}

struct LiveDetail: Hashable {
    var chase: String?        // "Australia need 126 runs in 63 balls."
    var crr: Double?
    var rrr: Double?
    var lastFive: String?     // "38/2 (7.60)"
    var overs: [OverSummary]  // oldest first, every over we fetched
    var batters: [BatterLine] = []
    var bowlers: [BowlerLine] = []
    var period = 0            // innings these figures belong to

    var rates: [(label: String, value: String)] {
        var out: [(label: String, value: String)] = []
        if let crr { out.append(("CRR", String(format: "%.2f", crr))) }
        if let rrr { out.append(("RRR", String(format: "%.2f", rrr))) }
        if let lastFive { out.append(("Last 5 ov", lastFive)) }
        return out
    }
}

// Cricinfo cuts rates down rather than rounding: 10 runs in 7 overs is 1.42, not 1.43.
func truncated2(_ x: Double) -> String {
    String(format: "%.2f", (x * 100 + 1e-9).rounded(.down) / 100)
}

struct BatterLine: Hashable {
    let id: String
    let name: String
    var shortName = ""
    let runs: Int
    let balls: Int
    let fours: Int
    let sixes: Int
    var onStrike = false

    var strikeRate: String {
        balls > 0 ? truncated2(Double(runs) * 100 / Double(balls)) : "-"
    }
}

struct BowlerLine: Hashable {
    let id: String
    let name: String
    var shortName = ""
    let balls: Int        // legal balls bowled
    let maidens: Int
    let conceded: Int
    let wickets: Int

    // 44 balls -> "7.2", 42 -> "7".
    var overs: String { balls % 6 == 0 ? "\(balls / 6)" : "\(balls / 6).\(balls % 6)" }
    var economy: String {
        balls > 0 ? truncated2(Double(conceded) * 6 / Double(balls)) : "-"
    }
    // VoiceOver: "7 overs 2 balls", not "seven point two".
    var oversSpoken: String {
        let o = balls / 6, b = balls % 6
        let overs = o == 1 ? "1 over" : "\(o) overs"
        return b == 0 ? overs : overs + (b == 1 ? " 1 ball" : " \(b) balls")
    }
}

// The two batters and two bowlers as of the latest ball that names them.
// Batters keep the order they first show up in. The feed has no batting
// position, so this is a best guess; ScoreStore keeps it steady across refreshes.
func playersFor(_ items: [PBPItem]) -> (batters: [BatterLine], bowlers: [BowlerLine]) {
    guard let at = items.lastIndex(where: { $0.batsman?.athlete?.id != nil }) else { return ([], []) }
    let latest = items[at]
    // Wickets on this ball or on a later item that names no players.
    let wickets = items[at...].filter { $0.dismissal?.dismissal == true }

    func batter(_ b: PBPBatter?) -> BatterLine? {
        guard let a = b?.athlete, let id = a.id, let name = a.displayName, !name.isEmpty else { return nil }
        return BatterLine(id: id, name: name, shortName: a.shortName ?? "", runs: b?.totalRuns ?? 0, balls: b?.faced ?? 0,
                          fours: b?.fours ?? 0, sixes: b?.sixes ?? 0)
    }
    func bowler(_ b: PBPBowler?) -> BowlerLine? {
        guard let a = b?.athlete, let id = a.id, let name = a.displayName, !name.isEmpty else { return nil }
        return BowlerLine(id: id, name: name, shortName: a.shortName ?? "", balls: b?.balls ?? 0, maidens: b?.maidens ?? 0,
                          conceded: b?.conceded ?? 0, wickets: b?.wickets ?? 0)
    }

    var batters = [batter(latest.batsman), batter(latest.otherBatsman)].compactMap { $0 }
    if !wickets.isEmpty {
        // The new batter isn't in the feed until they face. Show who's left,
        // with no strike mark (who faces next depends on whether they crossed).
        let out = Set(wickets.compactMap { $0.dismissal?.batsman?.athlete?.id })
        batters.removeAll { out.contains($0.id) }
    } else if let striker = batters.first, batters.count == 2 {
        // Who faces next: odd runs run swap ends, and so does the end of an over.
        // scoreValue includes the 1-run penalty for a wide or no-ball.
        let o = latest.over
        let penalty = ((o?.wide ?? 0) > 0 || (o?.noBall ?? 0) > 0) ? 1 : 0
        let ran = max(0, (latest.scoreValue ?? 0) - penalty)
        var swap = ran % 2 == 1
        if o?.complete == true { swap.toggle() }
        let next = swap ? batters[1].id : striker.id
        for i in batters.indices { batters[i].onStrike = batters[i].id == next }
    }
    var firstSeen: [String: Int] = [:]
    for (i, item) in items.enumerated() {
        for id in [item.batsman?.athlete?.id, item.otherBatsman?.athlete?.id].compactMap({ $0 }) where firstSeen[id] == nil {
            firstSeen[id] = i
        }
    }
    // Both seen on the same ball: the one with more balls faced most likely came in first.
    batters.sort { a, b in
        let fa = firstSeen[a.id] ?? .max, fb = firstSeen[b.id] ?? .max
        return fa != fb ? fa < fb : (a.balls, a.id) > (b.balls, b.id)
    }

    // Current bowler first.
    let bowlers = [bowler(latest.bowler), bowler(latest.otherBowler)].compactMap { $0 }
    return (batters, bowlers)
}

func ballFor(_ item: PBPItem) -> Ball {
    let runs = item.scoreValue ?? 0
    let o = item.over
    if item.dismissal?.dismissal == true { return Ball(label: "W", kind: .wicket, runs: runs) }
    if (o?.wide ?? 0) > 0 { return Ball(label: "\(runs)wd", kind: .extra, runs: runs) }
    if (o?.noBall ?? 0) > 0 { return Ball(label: "\(runs)nb", kind: .extra, runs: runs) }
    if (o?.legByes ?? 0) > 0 { return Ball(label: "\(runs)lb", kind: .extra, runs: runs) }
    if (o?.byes ?? 0) > 0 { return Ball(label: "\(runs)b", kind: .extra, runs: runs) }
    switch item.playType?.description {
    case "four": return Ball(label: "4", kind: .four, runs: runs)
    case "six": return Ball(label: "6", kind: .six, runs: runs)
    default: break
    }
    return runs == 0 ? Ball(label: "•", kind: .dot, runs: 0) : Ball(label: "\(runs)", kind: .runs, runs: runs)
}

private func fetchPBPPage(_ match: Match, page: Int) async throws -> PBPPage {
    var c = URLComponents(string: "https://site.web.api.espn.com/apis/site/v2/sports/cricket/\(match.leagueID)/playbyplay")!
    c.queryItems = [
        URLQueryItem(name: "event", value: match.id),
        URLQueryItem(name: "period", value: String(match.period)),
        URLQueryItem(name: "page", value: String(page)),
    ]
    var request = URLRequest(url: c.url!)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 20
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw FeedError.badStatus(http.statusCode)
    }
    return try JSONDecoder().decode(PBPResponse.self, from: data).commentary
}

// Pages are oldest-first, 25 balls each. Grab the last 2-3 pages so we
// have at least 5 overs for the "last 5 overs" number.
func fetchLiveDetail(_ match: Match) async throws -> LiveDetail? {
    let first = try await fetchPBPPage(match, page: 1)
    let lastPage = first.pageCount
    guard lastPage > 0 else { return nil }
    var items: [PBPItem] = []
    let firstPage = max(1, lastPage - 2)
    for p in firstPage...lastPage {
        items += p == 1 ? first.items : try await fetchPBPPage(match, page: p).items
    }
    return buildLiveDetail(items, period: match.period, startsMidInnings: firstPage > 1)
}

// Play-by-play items -> what the card shows. No network, so tests can feed it fixtures.
// startsMidInnings: items don't begin at page 1, so the oldest over is probably cut off.
func buildLiveDetail(_ items: [PBPItem], period: Int, startsMidInnings: Bool) -> LiveDetail? {
    // The feed sometimes ends with an empty filler item (no players, no team, zeroed rates). Skip it.
    guard let latest = items.last(where: { $0.batsman?.athlete?.id != nil || !($0.team?.displayName ?? "").isEmpty }) else { return nil }

    // Group balls by over number.
    var byOver: [Int: [Ball]] = [:]
    var wicketsByOver: [Int: Int] = [:]
    for item in items {
        guard let n = item.over?.number else { continue }
        let b = ballFor(item)
        byOver[n, default: []].append(b)
        if b.kind == .wicket { wicketsByOver[n, default: 0] += 1 }
    }
    let numbers = byOver.keys.sorted()
    // If we didn't start at page 1, the oldest over is probably cut off. Drop it.
    let shown = startsMidInnings && numbers.count > 1 ? Array(numbers.dropFirst()) : numbers
    let overs = shown.map { OverSummary(number: $0, balls: byOver[$0]!) }

    var detail = LiveDetail(overs: overs)
    (detail.batters, detail.bowlers) = playersFor(items)
    detail.period = period
    let inn = latest.innings
    detail.crr = inn?.runRate
    if let target = inn?.target, target > 0 {
        detail.rrr = inn?.requiredRunRate
        if let need = inn?.remainingRuns, need > 0 {
            let team = latest.team?.displayName ?? "They"
            if let balls = inn?.remainingBalls, (inn?.ballLimit ?? 0) > 0 {
                detail.chase = "\(team) need \(need) runs in \(balls) balls."
            } else {
                detail.chase = "\(team) need \(need) runs."
            }
        }
    }

    // Last 5 overs: the last 5 over numbers we have (current one included).
    let lastFive = numbers.suffix(5)
    if lastFive.count == 5 {
        let runs = lastFive.reduce(0) { $0 + byOver[$1]!.reduce(0) { $0 + $1.runs } }
        let wkts = lastFive.reduce(0) { $0 + (wicketsByOver[$1] ?? 0) }
        let legal = lastFive.reduce(0) { $0 + byOver[$1]!.filter { !$0.label.hasSuffix("wd") && !$0.label.hasSuffix("nb") }.count }
        let rr = legal > 0 ? Double(runs) / (Double(legal) / 6) : 0
        detail.lastFive = "\(runs)/\(wkts) (\(String(format: "%.2f", rr)))"
    }
    return detail
}
