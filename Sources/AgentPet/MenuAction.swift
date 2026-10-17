import AppKit

/// Retains a closure for a menu item; `NSMenuItem.target` is weak, so the item keeps this as its represented object.
@MainActor
final class MenuAction: NSObject {
    private let run: @MainActor () -> Void

    init(_ run: @escaping @MainActor () -> Void) {
        self.run = run
    }

    @objc func fire() {
        run()
    }
}

extension NSMenu {
    @MainActor @discardableResult
    func addAction(
        _ title: String, checked: Bool = false, enabled: Bool = true, run: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        addItem(item)
        return item
    }
}
