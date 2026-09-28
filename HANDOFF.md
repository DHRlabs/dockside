# Dockside handoff

## What Dockside is

Dockside is a native macOS app that shows AI usage meters in a small floating bubble beside the Dock. It follows the Dock's size, position, glass and visibility, and includes a right-end button strip for DHRlabs apps.

## Where it stands

- V0.1 through V0.3.1 are live, installed and tagged: `v0.1.0`, `v0.2.0`, `v0.3.0` and `v0.3.1`.
- V0.3.2 passed Opus review and is merged, installed and tagged `v0.3.2`.
- V0.5.0 was implemented by GPT-6 Luna, reviewed by GPT-6 Sol, signed, and installed in Applications as the only Dockside copy. It is live.
- Root's live Glass read showed 58% CPU, 87% RAM, and 76°C average CPU temperature. The Pixel screenshot showed 36% CPU, 87% RAM, and 79°C.
- Root clicked Show desktop once; it turned on and showed “Restore windows.” A second click turned it off and restored the windows. The Pixel preference survived app replacement and restart and remained selected.
- The widened Show desktop tile now sits fully inside the shared glass, with an adaptive native symbol.

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
2. Quit Dockside, replace `/Applications/Dockside.app` with `build/Dockside.app`, then open the installed app. Do not run a second copy.
3. Grant Accessibility permission once. Dockside opens at login when installed in Applications.

## Open items and next steps

1. Have Lance glance at light mode and Clear glass once.
2. V0.4 remains open for settings, an installer, and Lance's choice on bundling a zstd decoder. Claude decoding currently uses Homebrew's `zstd`.
3. GPU, network, disk, and battery stats remain future ideas.
4. More subscriptions (Cursor, DomoGPT credits, Gemini, Copilot, DeepSeek, OpenRouter) and Lance's own feeds remain future ideas.

## Known facts

- Claude numbers are only as fresh as the desktop app's saved copy. They turn gray after 15 minutes.
- Whether the Mini's Codex is the same account as this Mac's is unknown.
- System stats refresh every two seconds. CPU use needs a second counter sample; unavailable RAM or temperature stays `--`. Temperature averages CPU sensor keys currently verified on this Apple M5; other hardware may show `--`.
- The vault note `70 - Projects/Dockside.md` is the long-form history.
