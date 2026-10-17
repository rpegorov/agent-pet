import Foundation
import PetCore
import SwiftUI

/// Display strings and colours derived from a session; kept out of the views.
enum SessionPresentation {
    private static let sessionTailLength = 6

    static func projectName(of session: SessionState) -> String {
        if let cwd = session.cwd, !cwd.isEmpty {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            if !name.isEmpty, name != "/" { return name }
        }
        return String(session.session.suffix(sessionTailLength))
    }

    static func detail(of session: SessionState) -> String {
        session.label.isEmpty ? moodName(session.mood) : session.label
    }

    static func moodName(_ mood: Mood) -> String {
        mood.rawValue.capitalized
    }

    static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 1))
    }

    static func color(for mood: Mood) -> Color {
        switch mood {
        case .attention: .orange
        case .working: .green
        case .complete: .blue
        case .idle: .gray
        }
    }
}
