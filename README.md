# Dockside

Your AI usage, parked beside the Dock.

Dockside is a small native macOS app. A floating bubble sits just to the left of the Dock and shows how much of your AI coding allowances you have used.

It matches the Dock. Same height. Grows and shrinks when the Dock does. Hides and reappears when the Dock does, including in full-screen apps. It uses the empty space beside the Dock instead of the side of your screen.

## What it does

Each AI allowance gets one small vertical bar inside the bubble. The fill shows how much you have used. Hover the bubble for a plain-text summary with reset times. Right-click it to quit.

Sources:

- **Claude** usage comes from the numbers the Claude desktop app already saves on this Mac.
- **Codex** and **Grok** usage come from a small JSON feed the author runs at home. This is optional. Without it, those bars stay gray.

## Reading the bars

A thin white line across each bar shows how much of the time until the reset has passed. If the fill is above the line, you are on track to run out before it resets.

- **Red bar** : 10 percent or less of the allowance is left.
- **Gray bar** : no reading right now.

## Install and build

Requirements: macOS 14 or later. Built with Swift and AppKit, no third-party Swift packages.

Build from source:

```
bash Scripts/build.sh
```

Then open `build/Dockside.app`.

Status: early (version 0.1). Bottom Dock only for now.

## Permissions and privacy

**Accessibility** is the only permission Dockside needs, so it can find where the Dock is and how big it is.

Dockside reads no passwords, tokens, or sign-ins. For Claude it reads only the usage numbers the Claude desktop app has already saved on this Mac, and nothing else from that app. Decoding them currently uses the zstd library from Homebrew (`brew install zstd`); without it the Claude bars stay gray.

## Credits and license

The pace math and the Claude desktop usage read are adapted from [Codenotch](https://github.com/vinzdg/codenotch) by vinzdg (MIT). See NOTICE for details.

Dockside is licensed under the [MIT License](LICENSE).
