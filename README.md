# Dockside

Your AI usage, parked beside the Dock.

Dockside is a small native macOS app. A floating bubble sits just to the left of the bottom Dock and shows AI usage. A matching strip on the right shows CPU, RAM, and average CPU temperature.

## What it does

The bubble matches the Dock's height, glass, position, and visibility, including in full-screen apps. It follows your light or dark appearance, Liquid Glass, and Reduce Transparency settings, and uses the space beside the Dock.

The right strip follows the same Dock position and visibility. Its CPU and RAM dials use macOS readings, and its temperature averages CPU sensor keys currently verified on this Apple M5. Other hardware may show `--` for temperature. Missing readings show `--`; CPU use appears after the second sample. System stats hide beside a side Dock, while app buttons remain available there.

Right-click either surface and choose **Theme** to switch between **Glass** and **Pixel**. The choice is saved. Pixel uses stepped gauges and bars, dot-matrix temperature, and square accents while keeping the same glass backdrop.

Each meter shows its name and percent used above the bar, with the reset countdown below. Hover for 0.3 seconds to see pace details. Opens at login by default when installed in Applications. Right-click to turn that off or quit.

Sources:

- **Claude** usage comes from the numbers the Claude desktop app already saves on this Mac.
- **Codex** and **Grok** usage come from a small JSON feed the author runs at home. This is optional. Without it, those bars stay gray.

## Button strip

Dockside hosts a button at the outer end of the right strip when another app registers one. Other apps can add buttons through [PROTOCOL.md](PROTOCOL.md). The Show desktop button remains a full-size tile when idle.

## Reading the meters

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

For a live update, quit Dockside, replace `/Applications/Dockside.app` with the build, then open the installed app. Do not run a second copy beside it.

Status: version 0.5.0 live and installed.

## Permissions and privacy

**Accessibility** is the only permission Dockside needs, so it can find where the Dock is and how big it is.

Dockside reads no passwords, tokens, or sign-ins. For Claude it reads only the usage numbers the Claude desktop app has already saved on this Mac, and nothing else from that app. Decoding them currently uses the zstd library from Homebrew (`brew install zstd`); without it the Claude bars stay gray.

CPU and RAM readings come from this Mac's system counters. Temperature uses CPU sensor keys currently verified on this Apple M5; other hardware may show `--`. These readings do not use credentials or a network feed.

## Credits and license

The pace math and the Claude desktop usage read are adapted from [Codenotch](https://github.com/vinzdg/codenotch) by vinzdg (MIT). See NOTICE for details.

Dockside is licensed under the [MIT License](LICENSE).
