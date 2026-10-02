# Dockside

Your AI usage, parked beside the Dock.

Dockside is a small native macOS app. A floating bubble sits just to the left of the bottom Dock and shows AI usage. A matching strip on the right shows CPU, RAM, and average CPU temperature.

## What it does

The bubble matches the Dock's height, glass, position, and visibility, including in full-screen apps. Its text follows Dockside's light or dark appearance without changing color with the backdrop; the glass surface still responds to content behind it. Reduce Transparency remains respected, and it uses the space beside the Dock.

The right strip follows the same Dock position and visibility. Glass shows CPU and RAM in teal and orange upper semicircles, with centered percentages and readable labels below. Rounded Ticks uses the same layout with 13 round-ended ticks for each gauge. Average CPU temperature is a separate Celsius value above its own horizontal bar; the bar uses a fixed 0–100°C display scale with a green-yellow-red fill, while the number stays exact. This display scale is not an established hardware limit. Pixel keeps its thick two-row square-cell CPU/RAM arches and separate dot-matrix temperature with `°C`. Temperature averages CPU sensor keys currently verified on this Apple M5; other hardware may show `--`. Missing readings show `--`; CPU use appears after the second sample. System stats hide beside a side Dock, while app buttons remain available there.

Right-click either surface and choose **Theme** to switch between **Glass**, **Pixel**, and **Rounded Ticks**. The choice is saved. The right strip chooses its compact proportions when the full strip does not fit between the bottom Dock and the screen edge, and returns to the full layout when room allows. Compact Glass and Rounded Ticks keep readable labels and values while reducing gauge width and spacing.

Each AI meter shows its name and percent used above the bar, with the reset countdown below. Pixel and Rounded Ticks use segmented square AI bars in normal, compact, and hover views. Hover for 0.3 seconds to see pace details. Opens at login by default when installed in Applications. Right-click to turn that off or quit.

Sources:

- **Claude** usage comes from the numbers the Claude desktop app already saves on this Mac.
- **Codex** and **Grok** usage come from a small JSON feed the author runs at home. This is optional. Without it, those bars stay gray.

## Button strip

Dockside hosts app buttons at the outer end of the right strip. Other apps can add buttons through [PROTOCOL.md](PROTOCOL.md). Show desktop keeps a wide hit area and displays only its native icon, without a tile.

## Reading the meters

As left-side room narrows, the panel first shrinks beside the Dock, then switches to four labeled segmented level meters in a 180–216 pt compact layout. It moves above the Dock only when side space falls below 180 pt. The full view returns when room allows; normal drawing and hover details remain unchanged.

A vertical tick shows how much of the time window has passed. Reset countdowns can look like "5d 9h", "5h 12m", or "12m".

The hover card keeps one pace line, such as "14% under pace". Unavailable readings show "--", no reset or tick, and an empty track.

## Install and build

Requirements: macOS 14 or later. Built with Swift and AppKit, no third-party Swift packages.

Build from source:

```
bash Scripts/build.sh
```

Run the system-stats check and remove its temporary binary:

```sh
swiftc Sources/Dockside/SystemStats.swift Scripts/check-system-stats.swift -o /tmp/dockside-stats-check && /tmp/dockside-stats-check && rm -f /tmp/dockside-stats-check
```

Check compact-layout geometry:

```sh
bash Scripts/check-compact-layout.sh
```

For a live update, quit Dockside, replace `/Applications/Dockside.app` with the build, then open the installed app. Do not run a second copy beside it.

Status: version 0.5.8 is signed and installed as the single canonical copy; its signature and build match. The live right strip and production AI foreground fixture were inspected, and independent source/render review passed. The fixture capture omitted its backing window, so cross-background glass sampling and a direct live capture of the changed left panel remain unverified.

## Permissions and privacy

**Accessibility** is the only permission Dockside needs, so it can find where the Dock is and how big it is.

Dockside reads no passwords, tokens, or sign-ins. For Claude it reads only the usage numbers the Claude desktop app has already saved on this Mac, and nothing else from that app. Decoding them currently uses the zstd library from Homebrew (`brew install zstd`); without it the Claude bars stay gray.

CPU and RAM readings come from this Mac's system counters. Temperature uses CPU sensor keys currently verified on this Apple M5; other hardware may show `--`. These readings do not use credentials or a network feed.

## Credits and license

The pace math and the Claude desktop usage read are adapted from [Codenotch](https://github.com/vinzdg/codenotch) by vinzdg (MIT). See NOTICE for details.

Dockside is licensed under the [MIT License](LICENSE).
