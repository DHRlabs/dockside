# Dockside

Your AI usage, parked beside the Dock.

Dockside is a small native macOS app. A floating bubble sits just to the left of the bottom Dock and shows how much of your AI coding allowances you have used.

## What it does

The bubble matches the Dock's height, glass, position, and visibility, including in full-screen apps. It follows your light or dark appearance, Liquid Glass, and Reduce Transparency settings, and uses the space beside the Dock.

Each meter shows its name and percent used above the bar, with the reset countdown below. Hover for 0.3 seconds to see pace details. Opens at login by default when installed in Applications. Right-click to turn that off or quit.

Sources:

- **Claude** usage comes from the numbers the Claude desktop app already saves on this Mac.
- **Codex** and **Grok** usage come from a small JSON feed the author runs at home. This is optional. Without it, those bars stay gray.

## Button strip

Dockside hosts a button strip at the right end of the Dock. Other apps can add buttons through [PROTOCOL.md](PROTOCOL.md).

## Reading the meters

A vertical tick shows how much of the time window has passed. Reset countdowns can look like "5d 9h", "5h 12m", or "12m".

The hover card keeps one pace line, such as "14% under pace". Unavailable readings show "--", no reset or tick, and an empty track.

## Install and build

Requirements: macOS 14 or later. Built with Swift and AppKit, no third-party Swift packages.

Build from source:

```
bash Scripts/build.sh
```

Then open `build/Dockside.app`.

Status: early (version 0.3).

## Permissions and privacy

**Accessibility** is the only permission Dockside needs, so it can find where the Dock is and how big it is.

Dockside reads no passwords, tokens, or sign-ins. For Claude it reads only the usage numbers the Claude desktop app has already saved on this Mac, and nothing else from that app. Decoding them currently uses the zstd library from Homebrew (`brew install zstd`); without it the Claude bars stay gray.

## Credits and license

The pace math and the Claude desktop usage read are adapted from [Codenotch](https://github.com/vinzdg/codenotch) by vinzdg (MIT). See NOTICE for details.

Dockside is licensed under the [MIT License](LICENSE).
