import PetCore
import Testing
@testable import AgentPet

struct SpriteTimingTests {
    @Test func pingPongAvoidsTheJumpBack() {
        #expect(SpriteTiming.sequence(for: .working, frameCount: 4) == [0, 1, 2, 3, 2, 1])
        #expect(SpriteTiming.sequence(for: .idle, frameCount: 4) == [0, 1, 2, 3])
    }

    @Test func frameRatesMatchTheDesign() {
        #expect(SpriteLayout.framesPerSecond(for: .idle) == 2)
        #expect(SpriteLayout.framesPerSecond(for: .complete) == 2.5)
        #expect(SpriteLayout.framesPerSecond(for: .working) == 3)
        #expect(SpriteLayout.framesPerSecond(for: .attention) == 4)
    }

    @Test func cycleDurationMatchesTheFrameRate() {
        #expect(SpriteTiming.cycleDuration(for: .working, frameCount: 4) == 6 / 3)
        #expect(SpriteTiming.cycleDuration(for: .idle, frameCount: 4) == 4 / 2)
    }

    @Test func motionPerMood() {
        #expect(SpriteTiming.motion(for: .idle) == .breathing(scale: SpriteTiming.breathingScale, period: SpriteTiming.breathingPeriod))
        #expect(SpriteTiming.motion(for: .working) == .bob(amplitude: SpriteTiming.bobAmplitude, period: SpriteTiming.bobPeriod))
        #expect(SpriteTiming.motion(for: .attention) == .still)
        #expect(SpriteTiming.motion(for: .complete) == .still)
    }
}
