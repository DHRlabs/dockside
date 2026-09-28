import AppKit
import ServiceManagement

enum DockButtonPresentation: String, Equatable {
    case button
    case desktopStrip
}

struct DockButton {
    let provider: String
    let providerSession: String
    let buttonID: String
    let presentation: DockButtonPresentation
    var label: String
    var tooltip: String
    var enabled: Bool
    var toggled: Bool
    let symbol: String?
    let registrationOrder: Int
    var key: String { provider + "\u{0}" + buttonID }
}

@MainActor
final class DockButtonHost {
    private static let prefix = "com.dhrlabs.dockstrip.v1."
    private static let messageNames = ["discover", "register", "update", "remove", "result", "goodbye"]

    private struct PendingRequest {
        let provider: String
        let providerSession: String
        let buttonKey: String
        let expiresAt: TimeInterval
    }

    private let center = DistributedNotificationCenter.default()
    private let hostSession = UUID().uuidString
    private let onButtonsChanged: ([DockButton]) -> Void
    private var observerTokens: [NSObjectProtocol] = []
    private var ackTimer: Timer?
    private var buttons: [String: DockButton] = [:]
    private var providerSessions: [String: String] = [:]
    private var retiredProviderSessions: [String: Set<String>] = [:]
    private var pendingRequests: [String: PendingRequest] = [:]
    private var nextRegistrationOrder = 0
    private var canHostButtons = false

    init(onButtonsChanged: @escaping ([DockButton]) -> Void) {
        self.onButtonsChanged = onButtonsChanged
    }

    func start() {
        for suffix in Self.messageNames {
            let token = center.addObserver(
                forName: Notification.Name(Self.prefix + suffix), object: nil, queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let info = notification.userInfo ?? [:]
                MainActor.assumeIsolated { self?.receive(suffix, info) }
            }
            observerTokens.append(token)
        }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ackShownButtons() }
        }
        ackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        sendHostReady()
        publishButtons()
    }

    func stop() {
        post("goodbye", ["protocol": 1, "hostSession": hostSession])
        ackTimer?.invalidate()
        ackTimer = nil
        observerTokens.forEach { center.removeObserver($0) }
        observerTokens.removeAll()
        pendingRequests.removeAll()
    }

    func setCanHostButtons(_ canHost: Bool) {
        guard canHostButtons != canHost else { return }
        canHostButtons = canHost
        if canHost { Array(buttons.keys).forEach(ack) }
    }

    func invoke(_ key: String) {
        guard let button = buttons[key], button.enabled,
              !pendingRequests.values.contains(where: {
                  $0.buttonKey == key && $0.expiresAt > ProcessInfo.processInfo.systemUptime
              }) else { return }
        clearRequests(for: key)
        let requestID = UUID().uuidString
        pendingRequests[requestID] = PendingRequest(
            provider: button.provider, providerSession: button.providerSession, buttonKey: key,
            expiresAt: ProcessInfo.processInfo.systemUptime + 2
        )
        post("invoke", [
            "protocol": 1,
            "hostSession": hostSession,
            "provider": button.provider,
            "providerSession": button.providerSession,
            "buttonID": button.buttonID,
            "requestID": requestID
        ])
    }

    private func receive(_ suffix: String, _ info: [AnyHashable: Any]) {
        guard validProtocol(info["protocol"]) else { return }
        switch suffix {
        case "discover": receiveDiscover(info)
        case "register": receiveRegistration(info)
        case "update": receiveUpdate(info)
        case "remove": receiveRemoval(info)
        case "result": receiveResult(info)
        case "goodbye": receiveGoodbye(info)
        default: break
        }
    }

    private func receiveDiscover(_ info: [AnyHashable: Any]) {
        guard let provider = info["provider"] as? String,
              let session = info["providerSession"] as? String,
              UUID(uuidString: session) != nil, isRunning(provider) else { return }
        guard !retiredProviderSessions[provider, default: []].contains(session) else { return }
        if providerSessions[provider] != session {
            if providerSessions[provider] != nil { dropProvider(provider) }
            providerSessions[provider] = session
            publishButtons()
        }
        sendHostReady()
    }

    private func receiveRegistration(_ info: [AnyHashable: Any]) {
        guard let fields = parseButtonFields(info), isRunning(fields.provider) else { return }
        guard !retiredProviderSessions[fields.provider, default: []].contains(fields.providerSession) else { return }
        if let currentSession = providerSessions[fields.provider], currentSession != fields.providerSession {
            dropProvider(fields.provider)
        }
        providerSessions[fields.provider] = fields.providerSession
        let key = fields.provider + "\u{0}" + fields.buttonID
        clearRequests(for: key)
        let order = buttons[key]?.registrationOrder ?? nextRegistrationOrder
        if buttons[key] == nil { nextRegistrationOrder += 1 }
        buttons[key] = DockButton(
            provider: fields.provider, providerSession: fields.providerSession,
            buttonID: fields.buttonID, presentation: fields.presentation,
            label: fields.label, tooltip: fields.tooltip, enabled: fields.enabled,
            toggled: fields.toggled, symbol: fields.symbol, registrationOrder: order
        )
        publishButtons()
        if canHostButtons { ack(key) }
    }

    private func receiveUpdate(_ info: [AnyHashable: Any]) {
        guard let fields = parseButtonFields(info), isRunning(fields.provider),
              providerSessions[fields.provider] == fields.providerSession else { return }
        let key = fields.provider + "\u{0}" + fields.buttonID
        guard var button = buttons[key], button.providerSession == fields.providerSession else { return }
        button.label = fields.label
        button.tooltip = fields.tooltip
        button.enabled = fields.enabled
        button.toggled = fields.toggled
        buttons[key] = button
        publishButtons()
    }

    private func receiveRemoval(_ info: [AnyHashable: Any]) {
        guard let provider = info["provider"] as? String,
              let session = info["providerSession"] as? String,
              UUID(uuidString: session) != nil,
              let buttonID = info["buttonID"] as? String,
              buttonID.hasPrefix(provider + "."), isRunning(provider),
              providerSessions[provider] == session else { return }
        let key = provider + "\u{0}" + buttonID
        buttons.removeValue(forKey: key)
        clearRequests(for: key)
        publishButtons()
    }

    private func receiveResult(_ info: [AnyHashable: Any]) {
        guard let provider = info["provider"] as? String,
              let session = info["providerSession"] as? String,
              UUID(uuidString: session) != nil,
              let buttonID = info["buttonID"] as? String,
              buttonID.hasPrefix(provider + "."),
              let requestID = info["requestID"] as? String,
              UUID(uuidString: requestID) != nil,
              let outcome = info["outcome"] as? String,
              ["ok", "unavailable", "error"].contains(outcome),
              let toggled = boolean(info["toggled"]),
              providerSessions[provider] == session,
              let request = pendingRequests[requestID], request.provider == provider,
              request.providerSession == session,
              let button = buttons[request.buttonKey], button.buttonID == buttonID
        else { return }
        finishRequest(requestID)
        var updated = button
        updated.toggled = toggled
        buttons[request.buttonKey] = updated
        publishButtons()
    }

    private func receiveGoodbye(_ info: [AnyHashable: Any]) {
        guard let session = info["providerSession"] as? String,
              UUID(uuidString: session) != nil,
              let provider = providerSessions.first(where: { $0.value == session })?.key,
              info["provider"] == nil || (info["provider"] as? String) == provider else { return }
        dropProvider(provider)
        publishButtons()
    }

    private func parseButtonFields(_ info: [AnyHashable: Any]) -> (
        provider: String, providerSession: String, buttonID: String,
        presentation: DockButtonPresentation, label: String, tooltip: String,
        enabled: Bool, toggled: Bool, symbol: String?
    )? {
        guard let provider = info["provider"] as? String,
              let providerSession = info["providerSession"] as? String,
              UUID(uuidString: providerSession) != nil,
              let buttonID = info["buttonID"] as? String,
              buttonID.hasPrefix(provider + "."),
              let presentationName = info["presentation"] as? String,
              let presentation = DockButtonPresentation(rawValue: presentationName),
              let label = info["label"] as? String,
              let tooltip = info["tooltip"] as? String,
              let enabled = boolean(info["enabled"]),
              let toggled = boolean(info["toggled"])
        else { return nil }
        let symbol = info["symbol"] as? String
        if info["symbol"] != nil && symbol == nil { return nil }
        return (provider, providerSession, buttonID, presentation, label, tooltip, enabled, toggled, symbol)
    }

    private func finishRequest(_ requestID: String) {
        pendingRequests.removeValue(forKey: requestID)
    }

    private func clearRequests(for key: String) {
        for requestID in pendingRequests.compactMap({ $0.value.buttonKey == key ? $0.key : nil }) {
            finishRequest(requestID)
        }
    }

    private func dropProvider(_ provider: String) {
        if let session = providerSessions[provider] {
            retiredProviderSessions[provider, default: []].insert(session)
        }
        let keys = buttons.values.filter { $0.provider == provider }.map(\.key)
        keys.forEach {
            buttons.removeValue(forKey: $0)
            clearRequests(for: $0)
        }
        providerSessions.removeValue(forKey: provider)
    }

    private func publishButtons() {
        onButtonsChanged(Array(buttons.values))
    }

    private func ackShownButtons() {
        var removedProvider = false
        for provider in Set(buttons.values.map(\.provider)) where !isRunning(provider) {
            dropProvider(provider)
            removedProvider = true
        }
        if removedProvider { publishButtons() }
        guard canHostButtons else { return }
        Array(buttons.keys).forEach(ack)
    }

    private func ack(_ key: String) {
        guard let button = buttons[key] else { return }
        post("hostAck", [
            "protocol": 1,
            "hostSession": hostSession,
            "provider": button.provider,
            "buttonID": button.buttonID,
            "leaseSeconds": 10
        ])
    }

    private func sendHostReady() {
        post("hostReady", ["protocol": 1, "hostSession": hostSession])
    }

    private func post(_ suffix: String, _ userInfo: [String: Any]) {
        center.postNotificationName(Notification.Name(Self.prefix + suffix), object: nil,
                                    userInfo: userInfo, deliverImmediately: true)
    }

    private func isRunning(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isTerminated }
    }

    private func validProtocol(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return number.intValue == 1 && number.doubleValue == 1
    }

    private func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

@MainActor
final class DockStripPanel: NSPanel {
    private let stripView = DockStripView()
    private var location: DockLocation?
    private var pointerInside = false
    private var pendingLocation: DockLocation?
    var onInvoke: ((String) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = stripView
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        stripView.onInvoke = { [weak self] key in self?.onInvoke?(key) }
        stripView.onHoverChanged = { [weak self] inside in self?.hoverChanged(inside) }
        stripView.onPressStateChanged = { [weak self] pressed in
            if !pressed { self?.applyPendingLocation() }
        }
        orderOut(nil)
    }

    func update(_ buttons: [DockButton]) {
        stripView.update(buttons)
        guard stripView.hasButtons else {
            hideStrip()
            return
        }
        if let location { place(at: location) }
    }

    func place(at location: DockLocation?) {
        guard let location else {
            self.location = nil
            pendingLocation = nil
            if !pointerInside { hideStrip() }
            return
        }
        self.location = location
        guard stripView.hasButtons else { return }
        if stripView.hasPressedButton {
            pendingLocation = location
            return
        }
        apply(location)
    }

    func hideBecauseDockUnavailable() {
        location = nil
        pendingLocation = nil
        hideStrip()
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .rightMouseDown, let contentView else { return super.sendEvent(event) }
        DocksideContextMenu.popUp(with: event, for: contentView)
    }

    override func mouseDown(with event: NSEvent) {}
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func apply(_ location: DockLocation) {
        let side = location.orientation != .bottom
        let height = side ? location.frame.width : location.frame.height
        let totalWidth = stripView.width(for: height)
        guard height > 0, totalWidth > 0 else {
            hideStrip()
            return
        }
        let screen = location.screenFrame
        let frame: CGRect
        switch location.orientation {
        case .bottom:
            let x = location.frame.maxX + BubblePanel.dockGap
            if x + totalWidth <= screen.maxX {
                frame = CGRect(x: x, y: max(screen.minY, location.frame.minY - BubblePanel.dockPlateVerticalCalibration),
                               width: totalWidth, height: height)
            } else {
                let left = min(max(location.frame.maxX - totalWidth, screen.minX), screen.maxX - totalWidth)
                let y = min(screen.maxY - height, location.frame.maxY + BubblePanel.dockGap)
                frame = CGRect(x: left, y: y, width: totalWidth, height: height)
            }
        case .left:
            let below = location.frame.minY - BubblePanel.dockGap - height
            let y = below >= screen.minY ? below : min(max(location.frame.minY, screen.minY), screen.maxY - height)
            frame = CGRect(x: location.frame.minX, y: y, width: totalWidth, height: height)
        case .right:
            let below = location.frame.minY - BubblePanel.dockGap - height
            let y = below >= screen.minY ? below : min(max(location.frame.minY, screen.minY), screen.maxY - height)
            frame = CGRect(x: location.frame.maxX - totalWidth, y: y, width: totalWidth, height: height)
        }
        if self.frame != frame { setFrame(frame, display: true) }
        stripView.setItemHeight(height, orientation: location.orientation)
        if !isVisible { orderFrontRegardless() }
    }

    private func hoverChanged(_ inside: Bool) {
        pointerInside = inside
        if !inside && location == nil { hideStrip() }
    }

    private func applyPendingLocation() {
        guard !stripView.hasPressedButton, let pendingLocation else { return }
        self.pendingLocation = nil
        apply(pendingLocation)
    }

    private func hideStrip() {
        pointerInside = false
        orderOut(nil)
    }

    func refreshGlassAppearance() { stripView.refreshGlassAppearance() }
}

@MainActor
private final class DockStripView: NSView {
    private let ordinaryContent: NSView
    private let backdrop: GlassBackdropView
    private var itemViews: [String: DockStripButton] = [:]
    private var buttons: [DockButton] = []
    private var pressedKeys: Set<String> = []
    private var itemHeight: CGFloat = 0
    private var orientation: DockOrientation = .bottom
    var onInvoke: ((String) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onPressStateChanged: ((Bool) -> Void)?

    var hasPressedButton: Bool { !pressedKeys.isEmpty }
    var hasButtons: Bool { !buttons.isEmpty }

    override init(frame frameRect: NSRect) {
        ordinaryContent = NSView()
        backdrop = GlassBackdropView(contentView: ordinaryContent,
                                     cornerRadius: BubblePanel.dockPlateCornerRadius)
        super.init(frame: frameRect)
        addSubview(backdrop)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let ordinary = buttons.filter { $0.presentation == .button }
        let desktop = buttons.filter { $0.presentation == .desktopStrip }
        let desktopFirst = orientation == .left
        let visibleWidth = CGFloat(ordinary.count) * itemHeight + CGFloat(max(0, desktop.count - 1)) * 20 +
            (desktop.isEmpty ? 0 : 7)
        backdrop.frame = NSRect(x: desktopFirst ? CGFloat(desktop.count) * 20 - 7 : 0,
                                y: 0, width: visibleWidth, height: bounds.height)
        for (index, model) in ordinary.enumerated() {
            itemViews[model.key]?.frame = NSRect(x: CGFloat(index) * itemHeight, y: 0,
                                                  width: itemHeight, height: bounds.height)
        }
        let start = desktopFirst ? 0 : CGFloat(ordinary.count) * itemHeight
        for (index, model) in desktop.enumerated() {
            itemViews[model.key]?.frame = NSRect(x: start + CGFloat(index) * 20, y: 0,
                                                  width: 20, height: bounds.height)
        }
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    func update(_ buttons: [DockButton]) {
        self.buttons = sorted(buttons)
        let keys = Set(self.buttons.map(\.key))
        for key in itemViews.keys where !keys.contains(key) {
            itemViews.removeValue(forKey: key)?.removeFromSuperview()
        }
        for model in self.buttons {
            let item = itemViews[model.key] ?? makeButton(for: model)
            item.update(model, itemHeight: itemHeight, mirrorDesktopStrip: orientation == .left)
            let parent = model.presentation == .button ? ordinaryContent : self
            if item.superview !== parent {
                item.removeFromSuperview()
                parent.addSubview(item)
            }
            itemViews[model.key] = item
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func setItemHeight(_ height: CGFloat, orientation: DockOrientation) {
        guard itemHeight != height || self.orientation != orientation else { return }
        itemHeight = height
        self.orientation = orientation
        buttons = sorted(buttons)
        for model in buttons {
            itemViews[model.key]?.update(model, itemHeight: height, mirrorDesktopStrip: orientation == .left)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func width(for height: CGFloat) -> CGFloat {
        CGFloat(buttons.filter { $0.presentation == .button }.count) * height +
            CGFloat(buttons.filter { $0.presentation == .desktopStrip }.count) * 20
    }

    func refreshGlassAppearance() { backdrop.refreshAppearance() }

    private func sorted(_ buttons: [DockButton]) -> [DockButton] {
        buttons.sorted {
            if $0.presentation != $1.presentation {
                return orientation == .left ? $0.presentation == .desktopStrip : $0.presentation == .button
            }
            return $0.registrationOrder < $1.registrationOrder
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func makeButton(for model: DockButton) -> DockStripButton {
        let button = DockStripButton()
        button.onInvoke = { [weak self] key in self?.onInvoke?(key) }
        button.onPressStateChanged = { [weak self] key, pressed in
            guard let self else { return }
            if pressed { self.pressedKeys.insert(key) } else { self.pressedKeys.remove(key) }
            self.onPressStateChanged?(!self.pressedKeys.isEmpty)
        }
        return button
    }
}

@MainActor
private final class DockStripButton: NSButton {
    private var model: DockButton?
    private var hovered = false
    private var mirrorDesktopStrip = false
    var onInvoke: ((String) -> Void)?
    var onPressStateChanged: ((String, Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        target = self
        action = #selector(activate)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    func update(_ model: DockButton, itemHeight: CGFloat, mirrorDesktopStrip: Bool) {
        self.model = model
        self.mirrorDesktopStrip = mirrorDesktopStrip
        isEnabled = model.enabled
        toolTip = model.tooltip.isEmpty ? nil : model.tooltip
        setAccessibilityLabel(model.label)
        setAccessibilityValue(NSNumber(value: model.toggled))
        if model.presentation == .button {
            let symbol = NSImage(systemSymbolName: model.symbol ?? "circle", accessibilityDescription: model.label)
            let size = max(12, min(itemHeight * 0.46, 28))
            image = symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .regular))
            contentTintColor = isEnabled ? .labelColor : .secondaryLabelColor
        } else {
            image = nil
            contentTintColor = nil
        }
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let key = model?.key else { return }
        onPressStateChanged?(key, true)
        defer { onPressStateChanged?(key, false) }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let desktop = model.presentation == .desktopStrip
        let rect = desktop
            ? NSRect(x: mirrorDesktopStrip ? bounds.width - 7 : 1.5, y: 2,
                     width: 5.5, height: max(0, bounds.height - 4))
            : bounds.insetBy(dx: 5, dy: 5)
        let highlighted = model.toggled || (hovered && model.enabled)
        if highlighted {
            let alpha: CGFloat = model.toggled ? (hovered && model.enabled ? 0.30 : 0.18) : 0.16
            NSColor.controlAccentColor.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: desktop ? 3 : 11, yRadius: desktop ? 3 : 11).fill()
        }
        if desktop {
            NSColor.separatorColor.withAlphaComponent(0.65).setStroke()
            let separator = NSBezierPath()
            separator.lineWidth = 0.5
            let x = mirrorDesktopStrip ? bounds.width - 0.75 : 0.75
            separator.move(to: NSPoint(x: x, y: 5))
            separator.line(to: NSPoint(x: x, y: bounds.height - 5))
            separator.stroke()
        } else {
            super.draw(dirtyRect)
        }
        if !isEnabled, desktop {
            NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }
    }

    @objc private func activate() {
        guard isEnabled, let key = model?.key else { return }
        onInvoke?(key)
    }
}

@MainActor
enum DocksideContextMenu {
    static func popUp(with event: NSEvent, for view: NSView) {
        let menu = NSMenu()
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(AppDelegate.toggleOpenAtLogin(_:)),
                                 keyEquivalent: "")
        login.target = NSApp.delegate as? AppDelegate
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Dockside", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}
