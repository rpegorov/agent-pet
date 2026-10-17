import PetCore
import SwiftUI

enum PetMetrics {
    static let spriteSize: CGFloat = 192
    static let captionMaxWidth: CGFloat = 190
    static let captionPaddingH: CGFloat = 12
    static let captionPaddingV: CGFloat = 5
    static let captionSpacing: CGFloat = 6
    static let badgePaddingH: CGFloat = 10
    static let badgePaddingV: CGFloat = 4
    static let badgeOffset: CGFloat = 8
    static let itemWidth: CGFloat = 200
    static let itemHeight: CGFloat = 232
    static let outerPadding: CGFloat = 6
    static let badgeFillOpacity = 0.75
    static let badgeStrokeOpacity = 0.6
    static let badgeStrokeWidth: CGFloat = 1
}

struct PetView: View {
    let pet: PetState
    let hops: Int
    let actions: any PetActionHandling

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: PetMetrics.captionSpacing) {
                SpriteView(agent: pet.agent, mood: pet.mood)
                    .frame(
                        width: PetMetrics.spriteSize * SpriteLibrary.shared.canvasScale.width,
                        height: PetMetrics.spriteSize * SpriteLibrary.shared.canvasScale.height
                    )
                    .frame(width: PetMetrics.spriteSize, height: PetMetrics.spriteSize)
                CaptionView(text: caption)
            }
            .frame(width: PetMetrics.itemWidth, height: PetMetrics.itemHeight, alignment: .top)
            .modifier(HopEffect(trigger: hops))
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            PetHitArea(
                onClick: { actions.petClicked(agent: pet.agent) },
                onRightClick: { event, view in actions.showMenu(agent: pet.agent, event: event, in: view) }
            )
            .accessibilityHidden(true)

            if pet.sessions > 1 {
                Button { actions.toggleSessions(agent: pet.agent) } label: {
                    SessionBadge(count: pet.sessions)
                }
                .buttonStyle(.plain)
                .padding(.trailing, (PetMetrics.itemWidth - PetMetrics.spriteSize) / 2)
                .offset(x: PetMetrics.badgeOffset, y: -PetMetrics.badgeOffset)
                .modifier(HopEffect(trigger: hops))
                .accessibilityLabel("\(pet.sessions) sessions")
            }
        }
        .frame(width: PetMetrics.itemWidth, height: PetMetrics.itemHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(caption)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.petClicked(agent: pet.agent) }
    }

    private var caption: String {
        pet.label.isEmpty ? pet.agent : "\(pet.agent) · \(pet.label)"
    }
}

struct SessionBadge: View {
    let count: Int

    var body: some View {
        Text("×\(count)")
            .font(.callout.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, PetMetrics.badgePaddingH)
            .padding(.vertical, PetMetrics.badgePaddingV)
            .background(Capsule().fill(.black.opacity(PetMetrics.badgeFillOpacity)))
            .overlay(Capsule().strokeBorder(.white.opacity(PetMetrics.badgeStrokeOpacity), lineWidth: PetMetrics.badgeStrokeWidth))
    }
}

struct CaptionView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, PetMetrics.captionPaddingH)
            .padding(.vertical, PetMetrics.captionPaddingV)
            .frame(maxWidth: PetMetrics.captionMaxWidth)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}
