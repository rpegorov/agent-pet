import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PetStore()
    private let quiet = QuietMode()
    private var overlay: OverlayController?
    private var coordinator: OverlayCoordinator?
    private var demo: DemoFeeder?
    private var menu: OverlayMenu?
    private var interactor: OverlayInteractor?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = DemoFeeder(store: store)
        let menu = OverlayMenu(store: store, quiet: quiet, launcher: NewSessionLauncher(), runDemo: { demo.run() })
        let interactor = OverlayInteractor(store: store, jumper: SessionJumper(), menu: menu)
        self.demo = demo
        self.menu = menu
        self.interactor = interactor
        overlay = OverlayController(store: store, quiet: quiet, actions: interactor)
        coordinator = OverlayCoordinator(store: store, quiet: quiet)
        installStatusItem(menu: menu)
        quiet.start()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        quiet.stop()
        overlay?.stop()
    }

    private func installStatusItem(menu: OverlayMenu) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint", accessibilityDescription: "Agent Pet")
        item.menu = menu.makeStatusMenu()
        statusItem = item
    }
}
