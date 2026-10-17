import PetCore
import SwiftUI

struct PetRowView: View {
    private static let transitionOffset: CGFloat = 18
    private static let transitionDuration = 0.25

    let store: PetStore
    let context: PanelContext
    let actions: any PetActionHandling

    var body: some View {
        let columns = store.columns(showBubbles: context.showsBubbles)
        let popoverHeight = PetRowLayout.maxPopoverHeight(columns)
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(store.pets) { pet in
                column(for: pet, popoverHeight: popoverHeight)
                    .transition(.opacity.combined(with: .offset(y: Self.transitionOffset)))
            }
        }
        .animation(.easeOut(duration: Self.transitionDuration), value: store.pets.map(\.id))
        .padding(.horizontal, PetRowLayout.horizontalPadding)
        .padding(.bottom, PetRowLayout.bottomPadding)
        .padding(.top, PetRowLayout.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func column(for pet: PetState, popoverHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            if store.expandedAgent == pet.agent {
                SessionListView(sessions: store.sessions(of: pet.agent), actions: actions)
                    .padding(.bottom, PopoverMetrics.gap)
                    .transition(.opacity)
            }
            if context.showsBubbles, let bubble = store.bubbles[pet.agent] {
                PermissionBubbleView(bubble: bubble, actions: actions)
                    .id(bubble.id)
                    .padding(.bottom, PopoverMetrics.gap)
                    .transition(.opacity)
            }
            PetView(pet: pet, hops: store.hops[pet.agent] ?? 0, actions: actions)
        }
        .animation(.easeOut(duration: Self.transitionDuration), value: store.expandedAgent == pet.agent)
        .animation(.easeOut(duration: Self.transitionDuration), value: context.showsBubbles ? store.bubbles[pet.agent]?.id : nil)
        .frame(width: PetMetrics.itemWidth, height: PetMetrics.itemHeight + popoverHeight, alignment: .bottom)
    }
}
