import AppKit

/// Builds the status-bar menu and the per-pet context menu from the same pieces.
@MainActor
final class OverlayMenu: NSObject, NSMenuDelegate {
    private let store: PetStore
    private let quiet: QuietMode
    private let displays: DisplaySettings
    private let launcher: NewSessionLauncher
    private let runDemo: () -> Void

    init(store: PetStore, quiet: QuietMode, displays: DisplaySettings, launcher: NewSessionLauncher, runDemo: @escaping () -> Void) {
        self.store = store
        self.quiet = quiet
        self.displays = displays
        self.launcher = launcher
        self.runDemo = runDemo
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populate(menu, agent: nil)
        return menu
    }

    func makePetMenu(agent: String) -> NSMenu {
        let menu = NSMenu()
        populate(menu, agent: agent)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu, agent: nil)
    }

    private func populate(_ menu: NSMenu, agent: String?) {
        if let agent {
            addSessionToggle(to: menu, agent: agent)
            menu.addItem(.separator())
        }
        addNewSessionItems(to: menu)
        menu.addItem(.separator())
        addDisplayMenu(to: menu)
        addQuietItems(to: menu)
        menu.addItem(.separator())
        if agent == nil {
            menu.addAction("Demo") { [runDemo] in runDemo() }
            menu.addItem(.separator())
        }
        let quit = menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
    }

    private func addSessionToggle(to menu: NSMenu, agent: String) {
        let count = store.sessions(of: agent).count
        let expanded = store.expandedAgent == agent
        let title = expanded ? "Hide sessions" : "Show sessions (\(count))"
        menu.addAction(title, enabled: count > 0) { [store] in
            store.expandedAgent = expanded ? nil : agent
        }
    }

    private func addNewSessionItems(to menu: NSMenu) {
        menu.addAction("New Claude session") { [launcher] in launcher.newClaudeSession() }
        menu.addAction("New Codex session") { [launcher] in launcher.newCodexSession() }
        menu.addAction("New DSH chat") { [launcher] in launcher.newDshChat() }
        addTerminalSubmenu(to: menu, title: "Claude in Terminal", agent: .claude)
        addTerminalSubmenu(to: menu, title: "Codex in Terminal", agent: .codex)
    }

    private func addTerminalSubmenu(to menu: NSMenu, title: String, agent: NewSessionLauncher.TerminalAgent) {
        let submenu = NSMenu()
        let directories = store.recentDirectories
        if directories.isEmpty {
            submenu.addAction("No recent folders", enabled: false) {}
        }
        for directory in directories {
            let shown = (directory as NSString).abbreviatingWithTildeInPath
            submenu.addAction(shown) { [launcher] in launcher.start(agent, in: directory) }
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addDisplayMenu(to menu: NSMenu) {
        let submenu = NSMenu()
        let choice = displays.choice
        submenu.addAction("All displays", checked: choice == .all) { [displays] in displays.select(.all) }
        submenu.addItem(.separator())
        for display in displays.displays {
            let selected = choice == .screen(id: display.id, name: display.name)
            submenu.addAction(display.name, checked: selected) { [displays] in
                displays.select(.screen(id: display.id, name: display.name))
            }
        }
        let item = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addQuietItems(to menu: NSMenu) {
        if quiet.hiddenUntil != nil {
            menu.addAction("Show now") { [quiet] in quiet.show() }
        } else {
            menu.addAction("Hide for 1 hour") { [quiet] in quiet.hide() }
        }
        menu.addAction("Click-through", checked: quiet.clickThrough) { [quiet] in quiet.toggleClickThrough() }
        menu.addAction("Hide over full-screen apps", checked: quiet.hideOverFullScreen) { [quiet] in
            quiet.toggleHideOverFullScreen()
        }
        menu.addAction("Answer permissions from pet", checked: quiet.answerPermissions) { [quiet] in
            quiet.toggleAnswerPermissions()
        }
    }
}
