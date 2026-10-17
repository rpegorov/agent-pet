import Observation

/// Per-panel view state: with several panels, only one of them shows permission bubbles.
@MainActor
@Observable
final class PanelContext {
    var showsBubbles = false
}
