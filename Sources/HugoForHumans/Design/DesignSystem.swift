// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI

/// The app's visual language: one accent, generous type, and materials that
/// behave like a real Mac app rather than a web page in a window.
enum Design {

    // A single warm accent used sparingly, the way a Mac app should.
    static let accent = Color(red: 0.98, green: 0.45, blue: 0.20)
    static let accentSoft = Color(red: 0.98, green: 0.45, blue: 0.20).opacity(0.14)

    enum Metrics {
        static let corner: CGFloat = 10
        static let cardCorner: CGFloat = 14
        static let padding: CGFloat = 20
        static let tightPadding: CGFloat = 12
        static let sidebarWidth: CGFloat = 268
        static let inspectorWidth: CGFloat = 300
    }

    /// Standard card treatment: subtle fill, hairline border, soft shadow.
    static func card<Content: View>(_ content: Content, padding: CGFloat = Metrics.padding) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    static func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Shared components

/// A small labelled statistic, used on the dashboard.
struct StatTile: View {
    var value: String
    var label: String
    var icon: String
    var tint: Color = Design.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: Design.Metrics.cardCorner, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Metrics.cardCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Empty states that explain what to do next instead of showing an empty box.
struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// One row in the "what just happened" console.
struct LogRow: View {
    var line: SiteEngine.LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.time, format: .dateTime.hour().minute().second())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 58, alignment: .leading)
            Text(marker)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 10)
            Text(line.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(line.level == .command ? Color.primary : Color.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var marker: String {
        switch line.level {
        case .info: return "·"
        case .success: return "✓"
        case .warning: return "!"
        case .error: return "✕"
        case .command: return "$"
        }
    }

    private var color: Color {
        switch line.level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .command: return Design.accent
        }
    }
}

/// Consistent page header used by the main workspace screens.
struct WorkspaceHeader<Trailing: View>: View {
    var eyebrow: String?
    var title: String
    var subtitle: String?
    @ViewBuilder public var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Design.accent)
                }
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, Design.Metrics.padding)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
