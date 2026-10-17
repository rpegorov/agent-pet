import CoreGraphics
import Foundation
import PetCore

/// Pure description of sprite playback: frame order and the whole-figure motion laid over it.
/// Frames are hard cuts; blending two poses shows as a double image.
enum SpriteTiming {
    static let breathingScale: CGFloat = 0.015
    static let breathingPeriod: TimeInterval = 3
    static let bobAmplitude: CGFloat = 1.5
    static let bobPeriod: TimeInterval = 1.2

    enum Motion: Equatable {
        case still
        case breathing(scale: CGFloat, period: TimeInterval)
        case bob(amplitude: CGFloat, period: TimeInterval)
    }

    /// Rows whose last pose already leads back into the first loop; the others play forwards then backwards.
    static func loops(_ mood: Mood) -> Bool {
        switch mood {
        case .idle, .complete: true
        case .working, .attention: false
        }
    }

    static func sequence(for mood: Mood, frameCount: Int) -> [Int] {
        guard frameCount > 1 else { return Array(0..<max(frameCount, 0)) }
        let forward = Array(0..<frameCount)
        if loops(mood) { return forward }
        return forward + Array((1..<(frameCount - 1)).reversed())
    }

    static func cycleDuration(for mood: Mood, frameCount: Int) -> TimeInterval {
        Double(sequence(for: mood, frameCount: frameCount).count) / SpriteLayout.framesPerSecond(for: mood)
    }

    static func motion(for mood: Mood) -> Motion {
        switch mood {
        case .idle: .breathing(scale: breathingScale, period: breathingPeriod)
        case .working: .bob(amplitude: bobAmplitude, period: bobPeriod)
        case .attention, .complete: .still
        }
    }
}
