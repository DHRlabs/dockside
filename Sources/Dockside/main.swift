import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: BubblePanel!
    private var stripPanel: DockStripPanel!
    private var buttonHost: DockButtonHost!
    private var dockTracker: DockTracker!
    private var usagePoller: UsagePoller!

    private static let loginRegistrationAttemptedKey = "DocksideLoginRegistrationAttempted"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerLoginItemOnFirstLaunch()
        panel = BubblePanel()
        stripPanel = DockStripPanel()
        panel.onGlassAppearanceRefresh = { [weak stripPanel = self.stripPanel] in
            stripPanel?.refreshGlassAppearance()
        }
        stripPanel.onInvoke = { [weak self] key in self?.buttonHost.invoke(key) }
        buttonHost = DockButtonHost { [weak self] buttons in self?.stripPanel.update(buttons) }
        usagePoller = UsagePoller { [weak self] readings in
            self?.panel.update(readings)
        }
        dockTracker = DockTracker { [weak self] state in
            guard let self else { return }
            switch state {
            case .visible(let location):
                self.buttonHost.setCanHostButtons(true)
                self.stripPanel.place(at: location)
                self.panel.place(leftOf: location.orientation == .bottom ? location.frame : nil)
            case .hidden:
                self.buttonHost.setCanHostButtons(true)
                self.stripPanel.place(at: nil)
                self.panel.place(leftOf: nil)
            case .unavailable:
                self.buttonHost.setCanHostButtons(false)
                self.stripPanel.hideBecauseDockUnavailable()
                self.panel.place(leftOf: nil)
            }
        }
        usagePoller.start()
        dockTracker.start()
        buttonHost.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        buttonHost?.stop()
    }

    @objc func toggleOpenAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Dockside could not update Open at Login: %@", error.localizedDescription)
        }
    }

    private func registerLoginItemOnFirstLaunch() {
        let appPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        guard appPath.hasPrefix("/Applications/") else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.loginRegistrationAttemptedKey) else { return }
        if SMAppService.mainApp.status == .enabled {
            defaults.set(true, forKey: Self.loginRegistrationAttemptedKey)
            return
        }
        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: Self.loginRegistrationAttemptedKey)
        } catch {
            NSLog("Dockside could not register Open at Login: %@", error.localizedDescription)
        }
    }
}

let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
