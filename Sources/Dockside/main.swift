import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: BubblePanel!
    private var stripPanel: DockStripPanel!
    private var buttonHost: DockButtonHost!
    private var dockTracker: DockTracker!
    private var usagePoller: UsagePoller!
    private var systemStatsPoller: SystemStatsPoller!
    private(set) var selectedTheme: DocksideTheme = .glass

    private static let loginRegistrationAttemptedKey = "DocksideLoginRegistrationAttempted"
    private static let themePreferenceKey = "DocksideTheme"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerLoginItemOnFirstLaunch()
        selectedTheme = DocksideTheme(rawValue: UserDefaults.standard.string(forKey: Self.themePreferenceKey) ?? "") ?? .glass
        panel = BubblePanel()
        stripPanel = DockStripPanel()
        panel.setTheme(selectedTheme)
        stripPanel.setTheme(selectedTheme)
        panel.onGlassAppearanceRefresh = { [weak stripPanel = self.stripPanel] in
            stripPanel?.refreshGlassAppearance()
        }
        stripPanel.onInvoke = { [weak self] key in self?.buttonHost.invoke(key) }
        buttonHost = DockButtonHost { [weak self] buttons in self?.stripPanel.update(buttons) }
        usagePoller = UsagePoller { [weak self] readings in
            self?.panel.update(readings)
        }
        systemStatsPoller = SystemStatsPoller { [weak self] reading in
            self?.stripPanel.updateStats(reading)
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
        systemStatsPoller.start()
        dockTracker.start()
        buttonHost.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        buttonHost?.stop()
        systemStatsPoller?.stop()
    }

    @objc func selectTheme(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let theme = DocksideTheme(rawValue: rawValue) else { return }
        selectedTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.themePreferenceKey)
        panel.setTheme(theme)
        stripPanel.setTheme(theme)
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
