import AppKit

/// What one pet column currently shows above the pet.
struct PetColumn: Equatable {
    let agent: String
    let hasBubble: Bool
    let listRows: Int
}

enum SessionListLayout {
    static let maxVisibleSessions = 5

    /// Visible sessions plus one "more" row when the list is truncated.
    static func rowCount(sessions: Int) -> Int {
        sessions > maxVisibleSessions ? maxVisibleSessions + 1 : sessions
    }
}

enum PopoverMetrics {
    static let gap: CGFloat = 6
    static let bubbleWidth: CGFloat = 300
    static let bubbleBodyHeight: CGFloat = 262
    static let bubbleTextHeight: CGFloat = 160
    static let bubbleTailHeight: CGFloat = 9
    static let bubbleHeight: CGFloat = bubbleBodyHeight + bubbleTailHeight
    static let listWidth: CGFloat = 264
    static let listRowHeight: CGFloat = 42
    static let listPadding: CGFloat = 6
    static let hopHeight: CGFloat = 26

    static func listHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * listRowHeight + listPadding * 2
    }
}

/// Window geometry shared by the SwiftUI layout and the pass-through hit map.
enum PetRowLayout {
    @MainActor static var bottomPadding: CGFloat {
        let scale = SpriteLibrary.shared.canvasScale
        let overflow = PetMetrics.spriteSize * (max(scale.width, scale.height) - 1) / 2
        return max(PetMetrics.outerPadding, overflow.rounded(.up))
    }

    @MainActor static var topPadding: CGFloat { bottomPadding + PopoverMetrics.hopHeight }

    @MainActor static var horizontalPadding: CGFloat {
        max(bottomPadding, (max(PopoverMetrics.listWidth, PopoverMetrics.bubbleWidth) - PetMetrics.itemWidth) / 2)
    }

    static func popoverHeight(of column: PetColumn) -> CGFloat {
        var height: CGFloat = 0
        if column.hasBubble { height += PopoverMetrics.bubbleHeight + PopoverMetrics.gap }
        if column.listRows > 0 { height += PopoverMetrics.listHeight(rows: column.listRows) + PopoverMetrics.gap }
        return height
    }

    static func maxPopoverHeight(_ columns: [PetColumn]) -> CGFloat {
        columns.map(popoverHeight(of:)).max() ?? 0
    }

    @MainActor static func windowSize(columns: [PetColumn]) -> CGSize {
        CGSize(
            width: CGFloat(columns.count) * PetMetrics.itemWidth + horizontalPadding * 2,
            height: PetMetrics.itemHeight + maxPopoverHeight(columns) + bottomPadding + topPadding
        )
    }

    /// Screen rectangles that must receive clicks: each pet plus the bubble and list above it.
    @MainActor static func interactiveRects(columns: [PetColumn], windowFrame: NSRect) -> [NSRect] {
        var rects: [NSRect] = []
        for (index, column) in columns.enumerated() {
            let originX = windowFrame.maxX - horizontalPadding - CGFloat(columns.count - index) * PetMetrics.itemWidth
            let originY = windowFrame.minY + bottomPadding
            let centerX = originX + PetMetrics.itemWidth / 2
            rects.append(NSRect(x: originX, y: originY, width: PetMetrics.itemWidth, height: PetMetrics.itemHeight))
            var top = originY + PetMetrics.itemHeight + PopoverMetrics.gap
            if column.hasBubble {
                rects.append(NSRect(
                    x: centerX - PopoverMetrics.bubbleWidth / 2, y: top,
                    width: PopoverMetrics.bubbleWidth, height: PopoverMetrics.bubbleHeight))
                top += PopoverMetrics.bubbleHeight + PopoverMetrics.gap
            }
            if column.listRows > 0 {
                rects.append(NSRect(
                    x: centerX - PopoverMetrics.listWidth / 2, y: top,
                    width: PopoverMetrics.listWidth, height: PopoverMetrics.listHeight(rows: column.listRows)))
            }
        }
        return rects
    }
}
