import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class DockTracker {
    private let onState: (DockState) -> Void
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var promptedForAccessibility = false

    init(onState: @escaping (DockState) -> Void) {
        self.onState = onState
    }

    func start() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        poll()
        // ponytail: 500 ms visibility latency ceiling; use Dock AX notifications if tighter tracking is needed.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func poll() {
        guard AXIsProcessTrusted() else {
            onState(.unavailable)
            if !promptedForAccessibility {
                promptedForAccessibility = true
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            return
        }

        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first(where: { !$0.isTerminated }) else {
            onState(.unavailable)
            return
        }

        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        guard let children: [AXUIElement] = attribute(application, kAXChildrenAttribute),
              let list = children.first(where: { child in
                  AXUIElementSetMessagingTimeout(child, 0.1)
                  let role: String? = attribute(child, kAXRoleAttribute)
                  return role == (kAXListRole as String)
              }),
              let position: AXValue = attribute(list, kAXPositionAttribute),
              let size: AXValue = attribute(list, kAXSizeAttribute),
              let orientation: String = attribute(list, kAXOrientationAttribute)
        else {
            onState(.hidden)
            return
        }

        var axOrigin = CGPoint.zero
        var axSize = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &axOrigin),
              AXValueGetValue(size, .cgSize, &axSize),
              axSize.width > 0, axSize.height > 0,
              orientation == (kAXHorizontalOrientationValue as String) ||
                orientation == (kAXVerticalOrientationValue as String),
              let primaryScreenHeight = NSScreen.screens.first?.frame.height
        else {
            onState(.hidden)
            return
        }

        let frame = CGRect(
            x: axOrigin.x,
            y: primaryScreenHeight - axOrigin.y - axSize.height,
            width: axSize.width,
            height: axSize.height
        )
        let visibleScreens = NSScreen.screens.compactMap { screen -> (NSScreen, CGRect)? in
            let overlap = frame.intersection(screen.frame)
            return overlap.isNull || overlap.width <= 0 || overlap.height <= 0 ? nil : (screen, overlap)
        }
        guard let (screen, overlap) = visibleScreens.max(by: {
            $0.1.width * $0.1.height < $1.1.width * $1.1.height
        }) else {
            onState(.hidden)
            return
        }

        let dockOrientation: DockOrientation
        if orientation == (kAXHorizontalOrientationValue as String) {
            dockOrientation = .bottom
            guard overlap.height / frame.height >= 0.9, frame.midY <= screen.frame.midY else {
                onState(.hidden)
                return
            }
        } else {
            let leftDistance = abs(frame.minX - screen.frame.minX)
            let rightDistance = abs(screen.frame.maxX - frame.maxX)
            dockOrientation = leftDistance <= rightDistance ? .left : .right
            guard overlap.width / frame.width >= 0.9,
                  min(leftDistance, rightDistance) <= 80
            else {
                onState(.hidden)
                return
            }
        }
        onState(.visible(DockLocation(frame: frame, orientation: dockOrientation, screenFrame: screen.frame)))
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

enum DockOrientation: Equatable {
    case bottom
    case left
    case right
}

enum DockState {
    case visible(DockLocation)
    case hidden
    case unavailable
}

struct DockLocation {
    let frame: CGRect
    let orientation: DockOrientation
    let screenFrame: CGRect
}
