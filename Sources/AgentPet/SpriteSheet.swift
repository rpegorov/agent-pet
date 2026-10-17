import AppKit
import CoreGraphics
import PetCore

/// Grid layout of the sprite sheet: one row per mood, one column per frame.
enum SpriteLayout {
    static let rows = 4
    static let columns = 4
    static let resourceName = "catgirl-spritesheet"
    static let resourceExtension = "png"
    static let bytesPerPixel = 4
    static let bitsPerComponent = 8

    static func row(for mood: Mood) -> Int {
        switch mood {
        case .idle: 0
        case .working: 1
        case .attention: 2
        case .complete: 3
        }
    }

    static let idleFramesPerSecond = 2.0
    static let completeFramesPerSecond = 2.5
    static let workingFramesPerSecond = 3.0
    static let attentionFramesPerSecond = 4.0

    static func framesPerSecond(for mood: Mood) -> Double {
        switch mood {
        case .idle: idleFramesPerSecond
        case .complete: completeFramesPerSecond
        case .working: workingFramesPerSecond
        case .attention: attentionFramesPerSecond
        }
    }
}

/// Tinted, pre-cut frames for each agent, built once per agent.
@MainActor
final class SpriteLibrary {
    static let shared = SpriteLibrary()

    private var sheet: (pixels: [UInt8], segmentation: FrameSegmentation)?
    private var cache: [String: [Mood: [CGImage]]] = [:]

    private init() {
        sheet = Self.loadSheet()
    }

    /// Frame canvas size relative to one grid cell; the canvas is slightly larger than the cell.
    var canvasScale: CGSize {
        guard let segmentation = sheet?.segmentation else { return CGSize(width: 1, height: 1) }
        let cell = segmentation.cell(frame: 0)
        return CGSize(
            width: CGFloat(segmentation.canvasWidth) / CGFloat(cell.x1 - cell.x0),
            height: CGFloat(segmentation.canvasHeight) / CGFloat(cell.y1 - cell.y0)
        )
    }

    func frames(agent: String, mood: Mood) -> [CGImage] {
        let key = agent.lowercased()
        if cache[key] == nil {
            cache[key] = buildFrames(agent: key)
        }
        return cache[key]?[mood] ?? []
    }

    private static func loadSheet() -> (pixels: [UInt8], segmentation: FrameSegmentation)? {
        guard let url = Bundle.module.url(forResource: SpriteLayout.resourceName, withExtension: SpriteLayout.resourceExtension) else {
            NSLog("agent-pet: sprite sheet resource is missing from the bundle")
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            NSLog("agent-pet: could not read the sprite sheet: \(error)")
            return nil
        }
        guard
            let provider = CGDataProvider(data: data as CFData),
            let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else {
            NSLog("agent-pet: could not decode the sprite sheet")
            return nil
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * SpriteLayout.bytesPerPixel)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: SpriteLayout.bitsPerComponent,
                bytesPerRow: width * SpriteLayout.bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let segmentation = FrameSegmenter.segment(premultipliedRGBA: pixels, width: width, height: height)
        return (pixels, segmentation)
    }

    private func buildFrames(agent: String) -> [Mood: [CGImage]] {
        guard let sheet else { return [:] }
        var pixels = sheet.pixels
        if let hue = AgentPalette.targetHue(for: agent) {
            TintMath.tint(premultipliedRGBA: &pixels, targetHue: hue)
        }
        var result: [Mood: [CGImage]] = [:]
        for mood in Mood.allCases {
            let row = SpriteLayout.row(for: mood)
            result[mood] = (0..<SpriteLayout.columns).compactMap { column in
                sheet.segmentation.extract(frame: row * SpriteLayout.columns + column, from: pixels)
            }
        }
        return result
    }
}
