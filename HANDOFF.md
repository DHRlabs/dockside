# Dockside handoff

## What Dockside is

Dockside is a native macOS app that shows AI usage meters in a small floating bubble beside the Dock. It follows the Dock's size, position and visibility, uses opaque rounded backgrounds, and includes a right-end button strip for DHRlabs apps.

## Where it stands

- V0.1 through V0.3.1 are live, installed and tagged: `v0.1.0`, `v0.2.0`, `v0.3.0` and `v0.3.1`.
- V0.3.2 passed Opus review and is merged, installed and tagged `v0.3.2`.
- V0.5.0 was the prior live release, reviewed, signed, and installed. Glass showed 58% CPU, 87% RAM, and 76°C; Pixel showed 36% CPU, 87% RAM, and 79°C. Its saved Pixel choice survived restart.
- V0.5.1 was the prior live version. GPT-6 Sol passed all four component checks and final integration review, including the Grok marker repair.
- V0.5.2 was the prior live version. Its signed build passed, the installed app's signature was valid, and the build/install SHA-256 values matched (`09ef81a825fc5b163bc308c2bbcc511fa9967b47019a53afae42864fc3a645a7`). GPT-6 Sol passed its final source-review checks.
- V0.5.3 was the prior live version. Its signed build passed; the installed signature was valid, and build/install SHA-256 values matched (`6dae6a37520ae582cba7a4352dd541c2d5b639ae153590933491cef4ea6159bb`). GPT-6 Sol passed all four final review axes.
- V0.5.4 was the prior live version. Its signed copy's SHA-256 was `079711f0334103aaa178860d07dd15e2a82f80aaad5116f128a3366f702156c2`.
- V0.5.5 was the prior live version. Its signed binary SHA-256 was `67fd5d992ae9071e18c90d5835d941abefbcd8b27741785ce8e64da3df740e00`.
- V0.5.6 was the prior live version. Its signed binary SHA-256 was `cecf85a91965e5b4700542dd467bd82bb44d55facd904fad2427e8dcbbbd7d97`.
- V0.5.7 was the prior live version. Its signed binary SHA-256 was `73591148d7554919edd974a01b344e9633ac708ad4c7baa4e899be847fe4764b`.
- V0.5.8 was the prior live version. Its signed binary SHA-256 was `bbfd42893fbe2feb39909fb3279ca3ed9e5ea4b86e7203efe7432af765d5d24a`; signature was valid and build/install hashes matched. It used an adaptive glass surface beneath foreground content.
- V0.5.9 is live as the single canonical `/Applications` copy. Its signed binary SHA-256 is `0243bbf384af78802b9fd6ce9a580b9c3805dd59df0ff7023f126dfe8f6f72af`; signature is valid and build/install hashes match. Rounded Ticks remained selected after install.
- The live right panel showed 22% CPU, 86% RAM, and 69°C. Its text, gauges, temperature bar, and opaque rounded background were clear; the resolved background color had alpha 1.0. Show desktop was visible and off; no button action was tested. Source and executable checks found no behind-window effect classes, setting, polling, or refresh path.
- A live capture of the changed left panel was unavailable. The same opaque background component is used by the bubble and hover card; source and executable checks cover those shared surfaces.
- V0.5.4 used Glass B: smooth teal and orange CPU/RAM upper semicircles, centered values and labels below, and a separate Celsius number above the neutral 0–100°C temperature bar. Compact preserved readable labels and values; Pixel drawing was unchanged. The Show desktop hit area is 42–46 pt wide, leaving about 12–14 pt at the right edge.
- V0.5.5 adds Rounded Ticks beside Glass and Pixel. It uses the Glass labels, temperature display, compact spacing, and 3.49/3.00 width ratios, with 13 separate round-ended gauge ticks. GPT-6 Sol passed all four source/render review axes. Normal and compact renders with full and unknown readings passed, including compact 40/58/100 pt. All 24 Glass/Pixel renders match V0.5.4 byte-for-byte; protected components stayed unchanged except the theme enum.
- V0.5.6 colors the fixed 0–100°C temperature scale green to yellow to red, revealing the gradient only through the filled portion. This is a display scale, not an established hardware limit. Sol passed four preinstall review axes; boundary renders at 0/25/50/75/100/125°C and unavailable passed, with the exact 125°C label and full bar preserved. All 12 Pixel renders and unavailable Glass/Ticks renders match V0.5.5 byte-for-byte; the temperature bar is the only change.
- V0.5.7 gives Rounded Ticks the Pixel-style segmented AI usage bars in normal, compact, and hover views. Sol passed all four preinstall review axes. All 12 fixed-clock Rounded Ticks/Pixel render pairs (normal, compact, hover; populated and empty; 1x and 2x) match byte-for-byte.
- System-stats panel widths scale with Dock height and theme: Glass and Rounded Ticks are about 3.49/3.00 times height in normal/compact layouts; Pixel is about 3.96/3.28 times height. Compact mode is selected when the normal strip does not fit in the actual space to the right of the bottom Dock. The AI bubble and right stats choose compact layout independently. As left-side room narrows, the AI panel first shrinks beside the Dock, then uses four labeled segmented meters in a 180–216 pt layout. It moves above the Dock only below 180 pt; its normal drawing and hover details remain unchanged.
- V0.5.2 live checks showed Pixel at 11% CPU, 85% RAM, and 55°C, and Glass at 41% CPU, 86% RAM, and 77°C. Show desktop was verified off to on (“Restore windows”), then on to off with windows restored.
- V0.5.3 live checks showed Pixel at 26% CPU, 85% RAM, and 73°C. Glass first showed 97% CPU, 86% RAM, and 78°C, then 30% CPU, 86% RAM, and 70°C. Glass was selected. Show desktop was verified off to on (“Restore windows”), then on to off with windows restored. No Dock settings changed.
- V0.5.4 live checks at 58 pt showed Glass at 100% CPU, 86% RAM, and 98°C; after switching themes, Glass showed 25% CPU, 85% RAM, and 84°C. The semicircles, labels, temperature bar, and right padding were readable. Pixel showed 100% CPU, 86% RAM, and 98°C with its gauges unchanged. Show desktop was verified off to on (“Restore windows”), then on to off; Glass was restored.
- V0.5.5 live checks at 58 pt showed Glass at 25% CPU, 85% RAM, and 74°C; Rounded Ticks showed 20% CPU, 85% RAM, and 75°C, then 20% CPU, 85% RAM, and 70°C after restart. GPT-6 Sol independently passed the Rounded Ticks visual check at 30% CPU, 86% RAM, and 70°C: ticks were separated, text and temperature bar were readable, icon padding was comfortable, and Show desktop was off. After Pixel showed 40% CPU, 85% RAM, and 89°C, Glass was restored at 29% CPU, 85% RAM, and 91°C; Glass is selected. Show desktop was verified off to on (“Restore windows”), then on to off.
- V0.5.6 live checks at 58 pt showed Glass and Rounded Ticks at 71°C; Glass was restored at 73°C and selected. The green-yellow-orange fill and gray remainder were clear, with readable text and icons. GPT-6 Sol independently passed a native Glass inspection at 77°C (22% CPU, 86% RAM): the Celsius text, fill, icons, and padding were clear with no clipping. Show desktop was off.
- V0.5.7 restart retained Rounded Ticks. The visible right stats panel showed 47% CPU, 86% RAM, and 72°C; its temperature gradient was visible and Show desktop was off. The available live capture showed only the right stats panel, so the left AI bars and hover views were verified in production renders, not observed live.
- V0.5.4: GPT-6 Sol independently inspected the installed 58 pt Glass view through the app and accessibility data: 100% CPU, 85% RAM, 84°C; the semicircles, labels, temperature bar, and right padding were readable. Show desktop was off.
- Actual Dock-resize transitions have not been tested live. No Dock settings changed.

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

1. V0.4 remains open for settings, an installer, and Lance's choice on bundling a zstd decoder. Claude decoding currently uses Homebrew's `zstd`.
2. GPU, network, disk, and battery stats remain future ideas.
3. More subscriptions (Cursor, DomoGPT credits, Gemini, Copilot, DeepSeek, OpenRouter) and Lance's own feeds remain future ideas.

## Known facts

- Claude numbers are only as fresh as the desktop app's saved copy. They turn gray after 15 minutes.
- Whether the Mini's Codex is the same account as this Mac's is unknown.
- System stats refresh every two seconds. CPU use needs a second counter sample; unavailable RAM or temperature stays `--`. Temperature averages CPU sensor keys currently verified on this Apple M5; other hardware may show `--`.
- The vault note `70 - Projects/Dockside.md` is the long-form history.
