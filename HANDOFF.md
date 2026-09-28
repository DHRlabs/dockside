# Dockside handoff

## What Dockside is

Dockside is a native macOS app that shows AI usage meters in a small floating bubble beside the Dock. It follows the Dock's size, position, glass and visibility, and includes a right-end button strip for DHRlabs apps.

## Where it stands

- V0.1 through V0.3.1 are live, installed and tagged: `v0.1.0`, `v0.2.0`, `v0.3.0` and `v0.3.1`.
- V0.3.2 passed Opus review and is merged, installed and tagged `v0.3.2`.
- The button strip hosts Halfwin's Show desktop button (`Halfwin` main `32d78f5`), seen live at the right end of the Dock. The end-to-end click test is still needed: press twice to hide, then restore.

## Lance's decisions to keep

- Dockside is its own app, not a Halfwin feature.
- Claude comes from this Mac's Claude desktop app cache, with no credentials. Codex and Grok come from the Mini feed.
- Colors: Claude `#d97757`, Codex teal `#3fbfb2`, Grok white. No red and no “runs out”.
- Labels: `Claude 5h`, `Claude`, `Codex`, `Grok`. Never say “week”.
- Use HypeFarm's account meters as the model, not JScan. Keep the bubble at its existing width; it never grows to fit text. Put the countdown under each bar.

## How work is run

- The root orchestrates and never writes project files. GPT-6 Luna builds, usually at max reasoning (high for small fixes), through `CODEX_HOME=~/.codex-worker codex exec --profile worker -m gpt-6-luna -c model_reasoning_effort=max ... < /dev/null`.
- Opus reviews every change. Use GPT-6 Sol when Claude is limited.
- Commit, merge, push, install to `/Applications` and tag only after review passes and a live check.
- Test by installing, never by running a second copy. Two copies made the display flip between versions.

## How to build and run

1. Run `bash Scripts/build.sh <version>`.
2. Copy `build/Dockside.app` to `/Applications` and open it.
3. Grant Accessibility permission once. Dockside opens at login when installed in Applications.

## Open items and next steps

1. Run the Show desktop end-to-end test, pressing twice to hide and restore.
2. Have Lance glance at light mode and Clear glass once.
3. V0.4: settings, installer, and Lance's choice on bundling a zstd decoder. Claude decoding currently uses Homebrew's `zstd`.
4. V0.5 ideas: CPU, GPU, memory and temperature gauges; network, disk and battery; more subscriptions (Cursor, DomoGPT credits, Gemini, Copilot, DeepSeek, OpenRouter); Lance's own feeds.

## Known facts

- Claude numbers are only as fresh as the desktop app's saved copy. They turn gray after 15 minutes.
- Whether the Mini's Codex is the same account as this Mac's is unknown.
- The vault note `70 - Projects/Dockside.md` is the long-form history.
