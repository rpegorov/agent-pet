import CoreGraphics
import Foundation

/// Splits the sheet into per-frame pixel sets by content instead of by grid lines,
/// because the art crosses the nominal cell borders.
struct FrameSegmentation: Sendable {
    let width: Int
    let height: Int
    /// Frame index (row * columns + column) per pixel, or `unassigned`.
    let owner: [Int8]
    /// Transparent border added around every grid cell so overflowing art keeps its place.
    let margin: Int
    let canvasWidth: Int
    let canvasHeight: Int

    static let unassigned: Int8 = -1

    /// Grid cell edges come from floor(i * size / n).
    func cell(frame: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
        let column = frame % SpriteLayout.columns
        let row = frame / SpriteLayout.columns
        return (
            column * width / SpriteLayout.columns, row * height / SpriteLayout.rows,
            (column + 1) * width / SpriteLayout.columns, (row + 1) * height / SpriteLayout.rows
        )
    }

    /// Draws only this frame's pixels onto the shared canvas, keeping their offset from the cell.
    func extract(frame: Int, from pixels: [UInt8]) -> CGImage? {
        let cell = cell(frame: frame)
        let originX = cell.x0 - margin
        let originY = cell.y0 - margin
        let stride = SpriteLayout.bytesPerPixel
        var canvas = [UInt8](repeating: 0, count: canvasWidth * canvasHeight * stride)
        for y in max(0, originY)..<min(height, originY + canvasHeight) {
            for x in max(0, originX)..<min(width, originX + canvasWidth) {
                let source = y * width + x
                guard owner[source] == Int8(frame) else { continue }
                let target = ((y - originY) * canvasWidth + (x - originX)) * stride
                for channel in 0..<stride {
                    canvas[target + channel] = pixels[source * stride + channel]
                }
            }
        }
        return Self.makeImage(canvas, width: canvasWidth, height: canvasHeight)
    }

    static func makeImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var copy = pixels
        return copy.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: SpriteLayout.bitsPerComponent,
                bytesPerRow: width * SpriteLayout.bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }
}

enum FrameSegmenter {
    static let alphaThreshold: UInt8 = 16
    /// Row gaps are searched this far (px) around each nominal row border.
    static let cutSearchRadius = 48
    /// A fragment smaller than this share of its frame's largest component is dropped.
    static let minAreaShare = 0.01
    /// A fragment touching a row cut must reach this share of the largest component to be kept.
    static let minCutTouchingAreaShare = 0.25
    static let neighbourOffsets = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

    private struct Component {
        var pixels: [Int] = []
        var sumX = 0
        var sumY = 0
        var minX = Int.max, maxX = 0, minY = Int.max, maxY = 0
        var touchesCut = false
    }

    static func segment(premultipliedRGBA pixels: [UInt8], width: Int, height: Int) -> FrameSegmentation {
        let stride = SpriteLayout.bytesPerPixel
        let opaque = (0..<(width * height)).map { pixels[$0 * stride + 3] > alphaThreshold }
        let bandOfRow = rowBands(opaque: opaque, width: width, height: height)
        let components = label(opaque: opaque, width: width, height: height, bandOfRow: bandOfRow)

        var owner = [Int8](repeating: FrameSegmentation.unassigned, count: width * height)
        var assigned: [(component: Component, frame: Int)] = []
        var largestArea = [Int](repeating: 0, count: SpriteLayout.rows * SpriteLayout.columns)
        for component in components {
            let count = component.pixels.count
            let column = min(SpriteLayout.columns - 1, component.sumX / count * SpriteLayout.columns / width)
            let row = bandOfRow[min(height - 1, component.sumY / count)]
            let frame = row * SpriteLayout.columns + column
            largestArea[frame] = max(largestArea[frame], count)
            assigned.append((component, frame))
        }
        var margin = 0
        for (component, frame) in assigned where isFigure(component, largest: largestArea[frame]) {
            let column = frame % SpriteLayout.columns
            let row = frame / SpriteLayout.columns
            let x0 = column * width / SpriteLayout.columns
            let x1 = (column + 1) * width / SpriteLayout.columns
            let y0 = row * height / SpriteLayout.rows
            let y1 = (row + 1) * height / SpriteLayout.rows
            margin = max(margin, x0 - component.minX, component.maxX + 1 - x1, y0 - component.minY, component.maxY + 1 - y1)
            for index in component.pixels {
                owner[index] = Int8(frame)
            }
        }
        let cellWidth = (width + SpriteLayout.columns - 1) / SpriteLayout.columns
        let cellHeight = (height + SpriteLayout.rows - 1) / SpriteLayout.rows
        return FrameSegmentation(
            width: width, height: height, owner: owner, margin: margin,
            canvasWidth: cellWidth + 2 * margin, canvasHeight: cellHeight + 2 * margin
        )
    }

    /// Drops specks and pieces of a neighbouring figure that the row cut left behind.
    private static func isFigure(_ component: Component, largest: Int) -> Bool {
        let area = Double(component.pixels.count)
        let share = component.touchesCut ? minCutTouchingAreaShare : minAreaShare
        return area >= Double(largest) * share
    }

    /// Row index per pixel row; each border between rows is cut where the fewest opaque pixels sit.
    private static func rowBands(opaque: [Bool], width: Int, height: Int) -> [Int] {
        var cuts: [Int] = []
        for border in 1..<SpriteLayout.rows {
            let nominal = border * height / SpriteLayout.rows
            let candidates = max(1, nominal - cutSearchRadius)..<min(height, nominal + cutSearchRadius)
            let best = candidates.min { lhs, rhs in
                let left = opaqueCount(row: lhs, opaque: opaque, width: width)
                let right = opaqueCount(row: rhs, opaque: opaque, width: width)
                return left != right ? left < right : abs(lhs - nominal) < abs(rhs - nominal)
            }
            cuts.append(best ?? nominal)
        }
        return (0..<height).map { y in cuts.filter { y >= $0 }.count }
    }

    private static func opaqueCount(row: Int, opaque: [Bool], width: Int) -> Int {
        opaque[(row * width)..<((row + 1) * width)].reduce(0) { $0 + ($1 ? 1 : 0) }
    }

    /// 8-connected labelling that never joins pixels from different row bands.
    private static func label(opaque: [Bool], width: Int, height: Int, bandOfRow: [Int]) -> [Component] {
        var visited = [Bool](repeating: false, count: width * height)
        var components: [Component] = []
        for start in 0..<(width * height) where opaque[start] && !visited[start] {
            var component = Component()
            var stack = [start]
            visited[start] = true
            while let current = stack.popLast() {
                let x = current % width
                let y = current / width
                component.pixels.append(current)
                if (y > 0 && bandOfRow[y - 1] != bandOfRow[y]) || (y + 1 < height && bandOfRow[y + 1] != bandOfRow[y]) {
                    component.touchesCut = true
                }
                component.sumX += x
                component.sumY += y
                component.minX = min(component.minX, x)
                component.maxX = max(component.maxX, x)
                component.minY = min(component.minY, y)
                component.maxY = max(component.maxY, y)
                for (dx, dy) in neighbourOffsets {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height, bandOfRow[ny] == bandOfRow[y] else { continue }
                    let next = ny * width + nx
                    if opaque[next] && !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }
            components.append(component)
        }
        return components
    }
}
