import SwiftUI

// Shared look: sizes, colours and small reusable pieces.
enum Theme {
    static let panelWidth: CGFloat = 300
    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 11
    static let live = Color.red
    static let paused = Color.orange
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

    init(_ match: Match) {
        switch match.state {
        case "in": self = match.stateLabel.caseInsensitiveCompare("Live") == .orderedSame ? .live : .paused
        case "pre": self = .upcoming
        default: self = .finished
        }
    }
}

struct StatusPill: View {
    let match: Match
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

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
            if phase == .live {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                    .opacity(dim ? 0.35 : 1)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
                    }
            }
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
                Text(side.name)
                    .font(.system(size: 13, weight: batting ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                    Text(parts.main)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .fixedSize()
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
    }
}

// MARK: - Buttons and hover

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverPlate(pressed: configuration.isPressed, radius: 7) {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
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
        .padding(11)
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
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.tertiary)
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
