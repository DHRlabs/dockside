# Dockside handoff

## What Dockside is

Dockside is a native macOS app that shows AI usage meters in a small floating bubble beside the Dock. It follows the Dock's size, position, glass and visibility, and includes a right-end button strip for DHRlabs apps.

## Where it stands

- V0.1 through V0.3.1 are live, installed and tagged: `v0.1.0`, `v0.2.0`, `v0.3.0` and `v0.3.1`.
- V0.3.2 passed Opus review and is merged, installed and tagged `v0.3.2`.
- V0.5.0 was the prior live release, reviewed, signed, and installed. Glass showed 58% CPU, 87% RAM, and 76°C; Pixel showed 36% CPU, 87% RAM, and 79°C. Its saved Pixel choice survived restart.
- V0.5.1 was the prior live version. GPT-6 Sol passed all four component checks and final integration review, including the Grok marker repair.
- V0.5.2 is live and installed as the single copy in `/Applications`. Its signed build passed, the installed app's signature is valid, and the build/install SHA-256 values match (`09ef81a825fc5b163bc308c2bbcc511fa9967b47019a53afae42864fc3a645a7`). GPT-6 Sol passed all four final source-review checks after the 100% label fit fix.
- CPU/RAM use labeled vertical level meters in both layouts. Glass temperature uses a compact ring; Pixel uses a thick two-row square-cell arch with the Celsius value below it. The arc uses a 0–100°C visual scale while showing the exact reading. The saved Glass theme is active.
- Compact stats width is 150 pt; normal width remains height-based from 150 to 200 pt. The AI bubble and right stats choose compact layout independently. As left-side room narrows, the AI panel first shrinks beside the Dock, then uses four labeled segmented meters in a 180–216 pt layout. It moves above the Dock only below 180 pt; its normal drawing and hover details remain unchanged.
- Live V0.5.2 checks showed Pixel at 11% CPU, 85% RAM, and 55°C, and Glass at 41% CPU, 86% RAM, and 77°C. Both themes showed the level meters, matching temperature style, and icon-only Show desktop button. Show desktop was verified off to on (“Restore windows”), then on to off with windows restored. No Dock settings changed.
- Production compact renders at 58 pt Dock height covered both themes and the 100%/100°C case. The normal AI drawing was compared unchanged; compact AI renders were reviewed, but compact left-side behavior was not observed live. Geometry checks passed for right stats widths at 40, 58, and 100 pt Dock heights and the left compact threshold at 58 pt. Actual Dock-resize transitions have not been tested live.

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
4. Run `bash Scripts/check-compact-layout.sh` to check source layout geometry.

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
