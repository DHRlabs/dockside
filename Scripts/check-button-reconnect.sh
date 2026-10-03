#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
prefix="com.dhrlabs.dockstrip.check.$$.$RANDOM."

sed "s/com\\.dhrlabs\\.dockstrip\\.v1\\./$prefix/g" "$root/Sources/Dockside/DockStrip.swift" |
awk '/^@MainActor$/ { getline; if ($0 ~ /^final class DockStripPanel/) exit; print "@MainActor"; print; next } { print }' > "$temp/Check.swift"
cat >> "$temp/Check.swift" <<'SWIFT'

@MainActor
extension DockButtonHost {
    static func verifyReconnect() {
        let provider = "com.apple.finder"
        precondition(NSRunningApplication.runningApplications(withBundleIdentifier: provider).contains { !$0.isTerminated })
        let old = UUID().uuidString
        var buttons: [DockButton] = []
        let host = DockButtonHost { buttons = $0 }
        host.canHostButtons = true

        func send(_ suffix: String, _ info: [String: Any]) {
            var message = info
            message["protocol"] = 1
            host.receive(suffix, message)
        }
        func fields(_ session: String) -> [String: Any] {
            ["provider": provider, "providerSession": session, "buttonID": provider + ".show-desktop",
             "presentation": "desktopStrip", "label": "Show desktop", "tooltip": "Show desktop",
             "enabled": true, "toggled": false]
        }

        send("register", fields(old))
        send("goodbye", ["provider": provider, "providerSession": old])
        send("discover", ["provider": provider, "providerSession": old])
        send("register", fields(old))
        assert(buttons.count == 1 && buttons[0].providerSession == old, "retired live session did not reconnect")

        let current = UUID().uuidString
        send("discover", ["provider": provider, "providerSession": current])
        send("register", fields(current))
        send("discover", ["provider": provider, "providerSession": old])
        send("register", fields(old))
        assert(host.providerSessions[provider] == current, "stale session replaced current session")
        assert(buttons.count == 1 && buttons[0].providerSession == current, "stale session replaced current button")
        print("Button reconnect and stale-session checks passed")
    }
}

@main
struct ButtonReconnectCheck {
    @MainActor static func main() { DockButtonHost.verifyReconnect() }
}
SWIFT

swiftc -parse-as-library "$temp/Check.swift" -o "$temp/check"
"$temp/check"
