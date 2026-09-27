import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: BubblePanel!
    private var dockTracker: DockTracker!
    private var usagePoller: UsagePoller!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = BubblePanel()
        usagePoller = UsagePoller { [weak self] readings in
            self?.panel.update(readings)
        }
        dockTracker = DockTracker { [weak self] frame in
            self?.panel.place(leftOf: frame)
        }
        usagePoller.start()
        dockTracker.start()
    }
}

let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
