import PetCore
import SwiftUI

/// Speech bubble with the full pending permission request and Allow / Deny / Answer-in-agent buttons.
struct PermissionBubbleView: View {
    /// Buttons stay disabled for this long after the bubble content appears or changes.
    static let actionLockDuration: TimeInterval = 1

    private static let padding: CGFloat = 10
    private static let spacing: CGFloat = 6
    private static let cornerRadius: CGFloat = 14
    private static let countdownRefresh: TimeInterval = 0.25
    private static let textPadding: CGFloat = 6
    private static let textBackgroundOpacity = 0.18

    let bubble: PermissionBubble
    let actions: any PetActionHandling
    @State private var shownAt = Date()

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(Self.padding)
                .frame(width: PopoverMetrics.bubbleWidth, height: PopoverMetrics.bubbleBodyHeight, alignment: .top)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
            BubbleTail()
                .fill(.ultraThinMaterial)
                .frame(width: PopoverMetrics.bubbleTailHeight * 2, height: PopoverMetrics.bubbleTailHeight)
        }
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    if bubble.request.truncated {
                        Text("Input is too long to show in full. Answer in the agent to allow it.")
                            .font(.caption.weight(.semibold))
                    }
                    Text(bubble.request.toolInput.isEmpty ? bubble.request.summary : bubble.request.toolInput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Self.textPadding)
            }
            .frame(height: PopoverMetrics.bubbleTextHeight)
            .background(.black.opacity(Self.textBackgroundOpacity), in: RoundedRectangle(cornerRadius: Self.cornerRadius / 2))
            TimelineView(.periodic(from: .now, by: Self.countdownRefresh)) { context in
                VStack(spacing: Self.spacing) {
                    ProgressView(value: fraction(at: context.date))
                        .progressViewStyle(.linear)
                        .accessibilityHidden(true)
                    buttons(armed: context.date.timeIntervalSince(shownAt) >= Self.actionLockDuration)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Self.spacing) {
            Text("\(bubble.request.tool) · \(SessionPresentation.projectName(of: bubble.session))")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if bubble.total > 1 {
                Button("\(bubble.position) of \(bubble.total)") { actions.showNextRequest(agent: bubble.request.agent) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("Shows the next pending request")
            }
            TimelineView(.periodic(from: .now, by: Self.countdownRefresh)) { context in
                Text(verbatim: "\(remaining(at: context.date))s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func buttons(armed: Bool) -> some View {
        HStack {
            Button("Deny") { actions.answer(bubble, decision: .deny) }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            Button("In agent") { actions.answer(bubble, decision: .deferToAgent) }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Shows the agent's own permission dialog")
            if canAllow {
                Button("Allow") { actions.answer(bubble, decision: .allow) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(!armed)
    }

    private var canAllow: Bool { !bubble.request.truncated && !bubble.request.toolInput.isEmpty }

    private func remaining(at date: Date) -> Int {
        max(0, Int(expiry.timeIntervalSince(date).rounded(.up)))
    }

    private func fraction(at date: Date) -> Double {
        let total = bubble.request.expiresAt - bubble.request.ts
        guard total > 0 else { return 0 }
        return max(0, min(1, expiry.timeIntervalSince(date) / total))
    }

    private var expiry: Date { Date(timeIntervalSince1970: bubble.request.expiresAt) }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
