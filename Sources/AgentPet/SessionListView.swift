import PetCore
import SwiftUI

/// The expanded list of one agent's sessions; a row jumps to its session.
struct SessionListView: View {
    private static let dotSize: CGFloat = 10
    private static let rowSpacing: CGFloat = 10
    private static let rowPaddingH: CGFloat = 10
    private static let cornerRadius: CGFloat = 12
    private static let elapsedRefresh: TimeInterval = 5
    private static let hoverOpacity = 0.14

    let sessions: [SessionState]
    let actions: any PetActionHandling

    var body: some View {
        let shown = Array(sessions.prefix(SessionListLayout.maxVisibleSessions))
        let hidden = sessions.count - shown.count
        TimelineView(.periodic(from: .now, by: Self.elapsedRefresh)) { context in
            VStack(spacing: 0) {
                ForEach(shown) { session in
                    SessionRow(session: session, now: context.date) { actions.jump(to: session) }
                }
                if hidden > 0 {
                    Text("+\(hidden) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: PopoverMetrics.listRowHeight)
                }
            }
            .padding(PopoverMetrics.listPadding)
        }
        .frame(width: PopoverMetrics.listWidth, height: PopoverMetrics.listHeight(rows: SessionListLayout.rowCount(sessions: sessions.count)), alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .environment(\.colorScheme, .dark)
    }

    private struct SessionRow: View {
        let session: SessionState
        let now: Date
        let onSelect: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: SessionListView.rowSpacing) {
                    Circle()
                        .fill(SessionPresentation.color(for: session.mood))
                        .frame(width: SessionListView.dotSize, height: SessionListView.dotSize)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(SessionPresentation.projectName(of: session))
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(SessionPresentation.detail(of: session))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(SessionPresentation.elapsed(since: session.startedAt, now: now))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, SessionListView.rowPaddingH)
                .frame(height: PopoverMetrics.listRowHeight)
                .background(
                    RoundedRectangle(cornerRadius: SessionListView.cornerRadius / 2)
                        .fill(.white.opacity(hovering ? SessionListView.hoverOpacity : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(SessionPresentation.projectName(of: session)), \(SessionPresentation.moodName(session.mood)), \(SessionPresentation.detail(of: session))")
            .accessibilityHint("Opens the session")
        }
    }
}
