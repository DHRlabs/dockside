# Dockside working rules

Dockside is one native macOS app: a small floating bubble just left of the Dock that shows how much of
each AI allowance is used, with a pace line. It sizes itself to the Dock and hides and shows when the Dock
does. Human intent and decisions live in the DHRvault note `70 - Projects/Dockside.md`.

## Decisions (Lance, 2026-09-26)

- Its own app, not part of Halfwin. No menu bar icon and no Dock icon; right-click the bubble for its menu.
- Claude usage is this Mac's own account, read from the usage response the Claude desktop app already
  saved in its HTTP cache (Lance, 2026-09-26: the terminal Claude Code sign-in here is expired). Codex and
  Grok come from the Mini's usage feed at `https://crons.dhrlabs.com/api/account-usage.json`. Do not add a
  second reader for anything that feed already covers.
- Anchored left of the Dock. Bottom Dock first.
- Public open-source repo under DHRlabs, MIT.

## Licensing boundary

- Dockside is MIT. Codenotch (https://github.com/vinzdg/codenotch) is MIT: its techniques may be adapted
  with attribution in `NOTICE`. Halfwin is Lance's own MIT code and may be reused.
- GPL projects (DockDoor, AltTab, Loop, claude-notch and similar) are read-only for learning which system
  APIs exist. Never copy, translate or closely paraphrase their code.

## Credentials and privacy

- Dockside reads no credentials: no keychain, no tokens, no cookies. Keep it that way.
- The Claude desktop cache reader opens a cache file's body only when its key is exactly the claude.ai
  organizations usage URL, reads that body within the sizes the file's own records give, and decodes only
  the usage numbers. It never opens another entry's body, and it never parses, keeps or logs any bytes
  other than the decoded usage numbers. A damaged file yields no reading.
- No credential literals anywhere in the repo.

## Stack and build

- Swift, AppKit, SwiftPM executable, no Xcode project. This Mac has Command Line Tools only.
- Minimum macOS 14; use the system glass look where the SDK has it.
- `bash Scripts/build.sh` compiles, assembles `build/Dockside.app`, and signs it with the local
  "Apple Development" identity so the Accessibility grant survives rebuilds. It falls back to
  ad-hoc signing on machines without that identity.
- No third-party dependencies without Lance's yes.
- `build/` and `.build/` are never committed.
