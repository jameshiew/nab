# nab

A minimal shelf for macOS. Drag files onto a small panel that slides
in from the right edge of your screen, then drag them out to wherever you need
them.

## Requirements

- macOS 26 (Tahoe) or newer
- Xcode 26.4+ (Swift 6.3)

## Build & run

Open `Nab.xcodeproj` in Xcode and hit run, or from the command line:

```sh
xcodebuild -project Nab.xcodeproj -scheme Nab -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Nab-*/Build/Products/Debug/Nab.app
```

Nab runs as a menu bar app (no Dock icon). Quit it from the tray icon in the
status bar.

## How it works

- Start dragging any file anywhere on your Mac — the shelf slides in from the
  right edge.
- Drop the file on the shelf to park it.
- Drag rows out of the shelf to drop the files where you want them.
- Hover a row and click the × to remove it. The shelf auto-hides when empty
  and the drag is over.

Detection is via a global `NSEvent` mouse-drag monitor combined with polling
the system drag pasteboard for file URLs. Mouse-event monitors do not require
Accessibility permission.

## Linting & formatting

Code style is enforced with [`swift-format`](https://github.com/swiftlang/swift-format),
which ships with Xcode 26's toolchain. Configuration lives in
[`.swift-format`](./.swift-format). The Xcode `Lint` build phase runs
`swift-format lint` on every build and surfaces violations as warnings.

To format the codebase in place:

```sh
xcrun swift-format format -i -r Nab/
```

To check without modifying:

```sh
xcrun swift-format lint -r Nab/
```

## License

[MIT](./LICENSE).
