import SwiftUI
import AppKit

// Shared look: sizes, colours and small reusable pieces.
enum Theme {
    static let panelWidth: CGFloat = 300
    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 11
    static let live = Color(nsColor: dynamic(dark: .systemRed, light: NSColor(srgbRed: 0.72, green: 0.08, blue: 0.08, alpha: 1)))
    // Darker orange in light mode so small text stays readable.
    static let paused = Color(nsColor: dynamic(dark: .systemOrange, light: NSColor(srgbRed: 0.56, green: 0.28, blue: 0.0, alpha: 1)))

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

    private var tint: Color {
        switch phase {
        case .live: Theme.live
        case .paused: Theme.paused
        case .upcoming, .finished: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if phase == .live { LiveDot().id(reduceMotion) }
            Text(match.stateLabel.isEmpty ? "Unknown" : match.stateLabel)
                .font(.system(size: 9.5, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.4)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(tint.opacity(phase == .live || phase == .paused ? 0.15 : 0.10), in: Capsule())
        .fixedSize()
    }
}

// MARK: - Team row

struct SideRow: View {
    let side: Match.Side
    var batting = false

    var body: some View {
        let parts = ScoreParts(side.score)
        VStack(alignment: .trailing, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Full name if it fits, else the feed's short code.
                ViewThatFits(in: .horizontal) {
                    Text(side.name).lineLimit(1)
                    if !shortName.isEmpty { Text(shortName).lineLimit(1) }
                    Text(side.name).lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 13, weight: batting ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(side.name)
                if !parts.earlier.isEmpty {
                    Text(parts.earlier)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                }
                if !parts.main.isEmpty {
                    // Unusual long strings drop to a smaller size and can shrink, so they never overflow.
                    Text(parts.main)
                        .font(.system(size: parts.main.count > 9 ? 13 : 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
            }
            if !parts.detail.isEmpty {
                Text(parts.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side.score.isEmpty ? side.name : "\(side.name), \(side.score)")
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
                .foregroundStyle(.secondary)
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

struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            bar(width: 140, height: 8)
            HStack { bar(width: 90, height: 11); Spacer(); bar(width: 44, height: 14) }
            HStack { bar(width: 76, height: 11); Spacer(); bar(width: 56, height: 14) }
        }
        .padding(10)
        .cardBackground()
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

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
    }
}

extension View {
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }
}
