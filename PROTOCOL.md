# Dockside button strip protocol, version 1

Other apps put buttons in Dockside's strip at the right end of the Dock. Dockside draws and places the buttons and
handles clicks; the app that registered a button owns what it does and its state. Decision record: Dockside
ADR-001 in DHRvault.

## Transport

- `DistributedNotificationCenter.default()`, posted with `deliverImmediately: true`, `object: nil`.
- Every name starts with `com.dhrlabs.dockstrip.v1.`.
- `userInfo` holds only strings, numbers and booleans. Unknown keys are ignored. A message missing a required key,
  or with a wrong type or a different `protocol`, is dropped without a reply.
- Notifications are unauthenticated and can be delayed or dropped, so nothing here is privileged: a provider only
  runs actions it registered itself, and each side checks every field.

## Messages

| Name suffix | Sent by | Required keys | Meaning |
|---|---|---|---|
| `hostReady` | Dockside | `protocol` (1), `hostSession` | Dockside is running. Sent at launch and in reply to `discover`. |
| `discover` | provider | `protocol`, `provider`, `providerSession` | A provider started; asks any host to announce itself. |
| `register` | provider | `protocol`, `provider`, `providerSession`, `buttonID`, `presentation`, `label`, `tooltip`, `enabled`, `toggled`; optional `symbol` | Adds or replaces a button. |
| `update` | provider | same as `register` | Changes a button's label, tooltip, enabled or toggled state. |
| `remove` | provider | `protocol`, `provider`, `providerSession`, `buttonID` | Removes a button. |
| `hostAck` | Dockside | `protocol`, `hostSession`, `provider`, `buttonID`, `leaseSeconds` | Dockside is showing this button. Repeated every 3 seconds while shown; `leaseSeconds` is 10. |
| `invoke` | Dockside | `protocol`, `hostSession`, `provider`, `providerSession`, `buttonID`, `requestID` | The user clicked the button. |
| `result` | provider | `protocol`, `provider`, `providerSession`, `buttonID`, `requestID`, `outcome`, `toggled` | What the click did. `outcome` is `ok`, `unavailable` or `error`. |
| `goodbye` | either | `protocol` and that side's `hostSession` or `providerSession` | The sender is quitting; drop its buttons or its lease now. |

- `provider` is the provider's bundle identifier. `buttonID` must start with `provider` plus a dot, for example
  `com.dhrlabs.halfwin.show-desktop`.
- `hostSession`, `providerSession` and `requestID` are UUID strings, new for each launch or click.
- `presentation` is `desktopStrip` (the thin show desktop strip, always outermost) or `button`. `symbol` is an SF
  Symbol name, used only by `button`.
- `label` is the accessible name; `tooltip` is the hover text.

## Rules

- Ownership handoff: a provider shows its own fallback button until it receives `hostAck` for that button, hides it
  while acks keep arriving, and shows it again when no ack has arrived for `leaseSeconds` or when the host sends
  `goodbye`.
- Clicks: Dockside sends one `invoke` per click and never resends it. A provider handles each `requestID` at most
  once per `providerSession`. If no `result` arrives within 2 seconds, Dockside waits for the next `update` for
  that button instead of clicking again.
- Restarts: a new `providerSession` replaces every button from that provider's old session. A new `hostSession`
  means providers send `register` again for each of their buttons.
