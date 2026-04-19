# nab

A minimal vibe coded shelf for macOS. Drag files onto a small panel that slides
in from the right edge of your screen, then drag them out to wherever you need
them.

Nab runs as a menu bar app (no Dock icon). Quit it from the tray icon in the
status bar.

## Requirements

- macOS 26 (Tahoe) or newer
- Xcode 26.4+ (Swift 6.3)

## How it works

- Start dragging something anywhere on your Mac — the shelf slides in from the
  right edge.
- Drop onto the shelf to park it.
- Drag things out of the shelf to drop them where you want them.
- Hover over an item and click the × to remove it. The shelf auto-hides when empty
  and the drag is over.
