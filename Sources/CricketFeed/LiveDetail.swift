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
}

struct PBPType: Decodable { let description: String? }

struct PBPOver: Decodable {
    let number: Int?
    let overs: Double?
    let wide: Int?
    let noBall: Int?
    let legByes: Int?
    let byes: Int?
}

struct PBPInnings: Decodable {
    let runRate: Double?
    let requiredRunRate: Double?
    let remainingBalls: Int?
    let remainingRuns: Int?
    let target: Int?
    let ballLimit: Int?
}

struct PBPDismissal: Decodable { let dismissal: Bool? }

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
    var overs: [OverSummary]  // oldest first, last 2 overs

    var rates: [(label: String, value: String)] {
        var out: [(label: String, value: String)] = []
        if let crr { out.append(("CRR", String(format: "%.2f", crr))) }
        if let rrr { out.append(("RRR", String(format: "%.2f", rrr))) }
        if let lastFive { out.append(("Last 5 ov", lastFive)) }
        return out
    }
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
    for p in max(1, lastPage - 2)...lastPage {
        items += p == 1 ? first.items : try await fetchPBPPage(match, page: p).items
    }
    guard let latest = items.last else { return nil }

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
    let overs = numbers.suffix(2).map { OverSummary(number: $0, balls: byOver[$0]!) }

    var detail = LiveDetail(overs: overs)
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
