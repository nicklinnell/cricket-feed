import SwiftUI
import AppKit

// Shared look: sizes, colours and small reusable pieces.
enum Theme {
    static let panelWidth: CGFloat = 300
    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 11

    // Type scale. Keep to these so sizes read as clear steps.
    static let metaSize: CGFloat = 10.5    // venue, series, rates, footer
    static let bodySize: CGFloat = 12      // summary line
    static let teamSize: CGFloat = 14      // team names
    static let titleSize: CGFloat = 15     // panel title
    static let scoreSize: CGFloat = 19     // main score

    // Quiet text (series, venue, rates labels, footer). A fixed grey rather than
    // the system's vibrant .secondary, which fades to ~3.4:1 inside a mask.
    // Passes AA (4.5:1) on cards and the panel in both modes.
    static let meta = Color(nsColor: dynamic(dark: NSColor(white: 0.78, alpha: 1), light: NSColor(white: 0.37, alpha: 1)))

    // Fills (dot, chips) use these strong colours.
    static let live = Color(nsColor: dynamic(dark: .systemRed, light: NSColor(srgbRed: 0.72, green: 0.08, blue: 0.08, alpha: 1)))
    static let paused = Color(nsColor: dynamic(dark: .systemOrange, light: NSColor(srgbRed: 0.56, green: 0.28, blue: 0.0, alpha: 1)))

    // Text on a 15% tinted pill. Lighter in dark mode so it passes AA (4.5:1).
    static let liveInk = Color(nsColor: dynamic(dark: NSColor(srgbRed: 1.0, green: 0.75, blue: 0.71, alpha: 1), light: NSColor(srgbRed: 0.72, green: 0.08, blue: 0.08, alpha: 1)))
    static let pausedInk = Color(nsColor: dynamic(dark: NSColor(srgbRed: 1.0, green: 0.80, blue: 0.55, alpha: 1), light: NSColor(srgbRed: 0.56, green: 0.28, blue: 0.0, alpha: 1)))

    // Ball-by-ball chips. White text passes AA on all three in both modes.
    static let four = Color(nsColor: NSColor(srgbRed: 0.11, green: 0.48, blue: 0.21, alpha: 1))
    static let six = Color(nsColor: NSColor(srgbRed: 0.53, green: 0.26, blue: 0.75, alpha: 1))
    static let wicket = Color(nsColor: NSColor(srgbRed: 0.76, green: 0.13, blue: 0.13, alpha: 1))

    // Cards: near-white sheets in light mode, soft lift in dark. Live cards a touch brighter.
    static let cardFill = Color(nsColor: dynamic(dark: NSColor(white: 1, alpha: 0.045), light: NSColor(white: 1, alpha: 0.45)))
    static let cardFillLive = Color(nsColor: dynamic(dark: NSColor(white: 1, alpha: 0.08), light: NSColor(white: 1, alpha: 0.96)))
    static let cardStroke = Color(nsColor: dynamic(dark: NSColor(white: 1, alpha: 0.08), light: NSColor(white: 0, alpha: 0.08)))
    static let hairline = Color(nsColor: dynamic(dark: NSColor(white: 1, alpha: 0.09), light: NSColor(white: 0, alpha: 0.08)))

    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    // Header, footer, padding and a small margin above the screen edge.
    static let panelChrome: CGFloat = 96
}

// How much vertical space the panel has below its top edge. Updated by AppDelegate.
@MainActor
final class PanelRoom: ObservableObject {
    @Published var height: CGFloat = 800

    var maxListHeight: CGFloat { max(160, height - Theme.panelChrome) }
}

// MARK: - Score splitting

// "98 & 34/2 (12.3 ov, target 259)" -> earlier "98 &", main "34/2", detail "12.3 ov · target 259".
// Anything unexpected falls back to the whole string as `main`, so no text is lost.
struct ScoreParts: Equatable {
    var earlier = ""
    var main = ""
    var detail = ""

    init(_ score: String) {
        var head = score.trimmingCharacters(in: .whitespaces)
        if head.hasSuffix(")"), let r = head.range(of: " (", options: .backwards) {
            detail = head[r.upperBound...].dropLast()
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " · ")
            head = String(head[..<r.lowerBound])
        }
        if let r = head.range(of: " & ", options: .backwards) {
            earlier = String(head[..<r.lowerBound]) + " &"
            head = String(head[r.upperBound...])
        }
        main = head
    }
}

// MARK: - Match state

enum MatchPhase {
    case live      // in play
    case paused    // in, but Lunch / Stumps / Innings break etc.
    case upcoming
    case finished

    // Known pauses in play. Any other in-play label counts as live.
    private static let breaks = ["lunch", "tea", "dinner", "stumps", "drinks", "timeout", "innings break", "rain", "delayed", "bad light", "wet outfield", "interrupted"]

    init(_ match: Match) {
        switch match.state {
        case "in":
            let label = match.stateLabel.lowercased()
            self = Self.breaks.contains { label.contains($0) } ? .paused : .live
        case "pre": self = .upcoming
        default: self = .finished
        }
    }
}

// Pulsing dot. Own view so its state resets each time it reappears.
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Theme.live)
            .frame(width: 5, height: 5)
            .opacity(dim && !reduceMotion ? 0.35 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = !reduceMotion }
    }
}

struct StatusPill: View {
    let match: Match
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: MatchPhase { MatchPhase(match) }

    private var tinted: Bool { phase == .live || phase == .paused }

    private var ink: Color {
        switch phase {
        case .live: Theme.liveInk
        case .paused: Theme.pausedInk
        case .upcoming, .finished: Theme.meta
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if phase == .live { LiveDot().id(reduceMotion) }
            Text(match.stateLabel.isEmpty ? "Unknown" : match.stateLabel)
                .font(.system(size: 10, weight: tinted ? .bold : .semibold))
                .textCase(.uppercase)
                .kerning(0.5)
                .lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, tinted ? 7 : 0)
        .padding(.vertical, 3)
        .background(tinted ? AnyShapeStyle((phase == .live ? Theme.live : Theme.paused).opacity(0.15)) : AnyShapeStyle(.clear), in: Capsule())
        .fixedSize()
    }
}

// MARK: - Team row

struct SideRow: View {
    let side: Match.Side
    var batting = false
    // Live match where the other side is batting: this row steps back.
    var quiet = false

    var body: some View {
        let parts = ScoreParts(side.score)
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Full name if it fits, else the feed's short code.
                ViewThatFits(in: .horizontal) {
                    Text(side.name).lineLimit(1)
                    if !shortName.isEmpty { Text(shortName).lineLimit(1) }
                    Text(side.name).lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: Theme.teamSize, weight: batting ? .semibold : .regular))
                .foregroundStyle(quiet ? Theme.meta : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(side.name)
                if !parts.earlier.isEmpty {
                    Text(parts.earlier)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.meta)
                        .monospacedDigit()
                        .fixedSize()
                }
                if !parts.main.isEmpty {
                    // Unusual long strings drop to a smaller size and can shrink, so they never overflow.
                    Text(parts.main)
                        .font(.system(size: parts.main.count > 9 ? Theme.teamSize : Theme.scoreSize, weight: batting ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(quiet ? Theme.meta : Color.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
            }
            if !parts.detail.isEmpty {
                Text(parts.detail)
                    .font(.system(size: Theme.metaSize))
                    .foregroundStyle(Theme.meta)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side.score.isEmpty ? side.name : "\(side.name), \(side.score)" + (batting ? ", batting" : ""))
    }

    private var shortName: String {
        let s = side.short.trimmingCharacters(in: .whitespaces)
        return s == "?" || s == side.name ? "" : s
    }
}

// MARK: - Buttons and hover

struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HoverPlate(pressed: configuration.isPressed, radius: 7) {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.meta)
                .opacity(isEnabled ? 1 : 0.45)
                .frame(width: 24, height: 24)
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

// Rounded highlight that appears on hover and deepens on press.
struct HoverPlate<Content: View>: View {
    var pressed = false
    var selected = false
    var radius: CGFloat = 8
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var fill: Color {
        if pressed { return Color.primary.opacity(0.14) }
        if hovering { return Color.primary.opacity(0.08) }
        if selected { return Color.accentColor.opacity(0.10) }
        return .clear
    }
}

// MARK: - Placeholders

// Same shape as a real card, so the panel barely moves when scores land.
struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { bar(width: 130, height: 9); Spacer(); bar(width: 40, height: 14) }
            bar(width: 170, height: 7).padding(.top, 6)
            HStack { bar(width: 110, height: 14); Spacer(); bar(width: 50, height: 19) }.padding(.top, 14)
            HStack { bar(width: 90, height: 14); Spacer(); bar(width: 42, height: 19) }.padding(.top, 8)
            bar(width: 180, height: 10).padding(.top, 22)
            bar(width: 150, height: 9).padding(.top, 8)
        }
        .padding(12)
        .cardBackground()
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var action: (title: String, run: () -> Void)?
    // Blue for an invitation, grey for problems.
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.12), in: Circle())
                .padding(.bottom, 6)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: Theme.bodySize))
                .foregroundStyle(Theme.meta)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }
}

extension View {
    func cardBackground(prominent: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(prominent ? Theme.cardFillLive : Theme.cardFill)
                .strokeBorder(Theme.cardStroke, lineWidth: 0.5)
        )
    }
}
