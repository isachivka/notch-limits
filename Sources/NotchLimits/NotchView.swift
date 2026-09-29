import NotchLimitsCore
import ServiceManagement
import SwiftUI

enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.36, green: 0.66, blue: 1.0)
    static let warm = Color(red: 1.0, green: 0.76, blue: 0.3)
    static let hot = Color(red: 1.0, green: 0.36, blue: 0.37)

    static func accent(_ kind: ProviderKind) -> Color {
        kind == .claude ? claude : codex
    }

    static func fill(_ kind: ProviderKind, percent: Double) -> Color {
        switch UsageLevel(percent: percent) {
        case .calm: accent(kind)
        case .warm: warm
        case .hot: hot
        }
    }
}

struct NotchView: View {
    let model: NotchModel
    let store: UsageStore

    private let collapsedTopRadius: CGFloat = 8
    /// Same gap from the black edge on the left, right and bottom.
    static let inset: CGFloat = 14

    var body: some View {
        let expanded = model.isExpanded
        let size = expanded
            ? model.expandedSize
            : CGSize(width: model.notchSize.width + collapsedTopRadius * 2, height: model.notchSize.height)
        let shape = NotchShape(topRadius: expanded ? NotchModel.topRadius : collapsedTopRadius,
                               bottomRadius: expanded ? NotchModel.bottomRadius : 10)

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(expanded ? 0.55 : 0), radius: 18, y: 8)

            // Always laid out at full width so its height can be measured
            // before the first open; hidden and clipped while collapsed.
            PanelContent(model: model, store: store)
                .padding(.horizontal, NotchModel.topRadius + Self.inset)
                .padding(.bottom, Self.inset)
                .frame(width: NotchModel.width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { model.contentHeight = $0 }
                .opacity(expanded ? 1 : 0)
                .scaleEffect(expanded ? 1 : 0.92, anchor: .top)
                .blur(radius: expanded ? 0 : 8)
                .animation(expanded
                    ? .spring(response: 0.4, dampingFraction: 0.8).delay(0.05)
                    : .easeOut(duration: 0.12), value: expanded)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
                .allowsHitTesting(expanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .contextMenu {
            Button("Refresh") { store.refresh() }
            LaunchAtLoginToggle()
            Divider()
            Button("Quit Notch Limits") { NSApp.terminate(nil) }
        }
    }
}

private struct PanelContent: View {
    let model: NotchModel
    let store: UsageStore

    var body: some View {
        VStack(spacing: 10) {
            header.frame(height: model.notchSize.height)
            let items = store.visible
            if items.isEmpty {
                EmptyState()
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(items, id: \.0) { kind, status in
                        ProviderCard(kind: kind, status: status, throttledUntil: store.throttledUntil[kind])
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Lives in the strips left and right of the physical notch.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: [Palette.claude, Palette.codex],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7, height: 7)
                Text("Limits")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: model.notchSize.width)
            TimelineView(.periodic(from: .now, by: 10)) { context in
                HStack(spacing: 6) {
                    if let last = store.lastRefresh {
                        Text(ResetFormatter.ago(last, now: context.date))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    RefreshButton(spinning: store.isRefreshing) { store.refresh() }
                }
            }
        }
    }
}

private struct RefreshButton: View {
    let spinning: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(hover ? 0.9 : 0.5))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                           value: spinning)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(hover ? 0.12 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct ProviderCard: View {
    let kind: ProviderKind
    let status: ProviderStatus
    let throttledUntil: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderGlyph(kind: kind)
                Text(kind.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                if let plan = status.snapshot?.plan {
                    Text(plan)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.accent(kind))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Palette.accent(kind).opacity(0.16)))
                }
            }

            switch status {
            case .loading, .notConfigured:
                ForEach(0..<2, id: \.self) { _ in
                    UsageRow(kind: kind, window: UsageWindow(label: "Loading", usedPercent: 0, resetsAt: nil))
                        .redacted(reason: .placeholder)
                }
            case .ok(let snap):
                rows(snap)
            case .failed(let message, let last):
                if let last { rows(last).opacity(0.45) }
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.warm)
                    .lineLimit(1)
            }
            if let until = throttledUntil, status.snapshot != nil {
                TimelineView(.periodic(from: .now, by: 20)) { context in
                    if until > context.date {
                        Label("Rate limited · retry in \(ResetFormatter.string(until: until, now: context.date))",
                              systemImage: "hourglass")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.03)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func rows(_ snap: ProviderSnapshot) -> some View {
        VStack(spacing: 10) {
            ForEach(snap.windows) { UsageRow(kind: kind, window: $0) }
        }
    }
}

private struct ProviderGlyph: View {
    let kind: ProviderKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.accent(kind).opacity(0.18))
            switch kind {
            case .claude:
                Starburst().fill(Palette.claude).padding(4)
            case .codex:
                OpenAIMark().fill(.white).padding(3.5)
            }
        }
        .frame(width: 20, height: 20)
    }
}

struct UsageRow: View {
    let kind: ProviderKind
    let window: UsageWindow

    var body: some View {
        let color = Palette.fill(kind, percent: window.usedPercent)
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                if let reset = window.resetsAt {
                    TimelineView(.periodic(from: .now, by: 20)) { context in
                        Text("↻ \(ResetFormatter.string(until: reset, now: context.date))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(window.usedPercent.rounded()))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(window.usedPercent >= 60 ? color : .white)
            }
            UsageBar(percent: window.usedPercent, color: color)
        }
    }
}

private struct UsageBar: View {
    let percent: Double
    let color: Color
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            let fraction = max(0, min(1, shown / 100))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.55), color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(fraction > 0 ? 5 : 0, geo.size.width * fraction))
                    .shadow(color: color.opacity(0.7), radius: 5)
            }
        }
        .frame(height: 5)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.12)) { shown = percent }
        }
        .onChange(of: percent) { _, new in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shown = new }
        }
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.4))
            Text("Sign in to Claude Code or Codex on this Mac")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("NotchLimits: launch at login: \(error)")
                }
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
    }
}
