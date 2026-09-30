# Bobby

Bobby is a small macOS scratchpad for quick maths, currency conversions, and
simple interest. Type a calculation, see the answer, and keep notes alongside it.

Open it with a keyboard shortcut whenever you need a little room for your
numbers. Keep separate scratches for different thoughts, with everything saved
on your Mac.

## Examples

```text
11.5m * 2%
0.1 + 0.2
rent = 25000
rent * 12
500 USD to TL
TL euro
interest = 500k TL at 40% for 32 days
interest * .75
```

Answers update as you type. Click one to copy it, or hover for details. Named
values let you reuse a calculation on later lines in the same scratch.

Bobby understands English and Turkish finance terms, with English number
formatting (`1,234.56`). When supported wording needs clarification, it offers an
interpretation for you to review.

Currency conversions show their source and date. These are reference rates,
which may differ from your bank's quote. Cached rates remain available offline,
and you can refresh them from the More menu.

Interest calculations show gross interest and the final balance before
deductions. They use simple interest with a visible year basis, initially 365
days, which you can change in the footer.

## Tutorial

Choose **Take a tour** for six short lessons and examples you can play with.
The practice area is separate from your saved scratches, so feel free to try
things out. Press Escape or click outside to close it.

## Keyboard and storage

- `Control+Option+B`: show or hide Bobby from any app, configurable in Settings.
- `Escape`: hide the scratchpad.
- `Command+N`: new scratch.
- `Command+Shift+C`: copy the answer on the current line.
- `Command+Option+Left/Right`: previous/next scratch.
- `Command+Shift+S`: export source text. Markdown export is in the More menu.

You can also swipe left or right with two fingers to preview a neighboring
scratch. Swipe far enough and release to switch, or make a short swipe to settle
back. Scroll vertically as usual.

Scratches autosave and return when you reopen Bobby. There is no account or
cloud sync. Local data lives in `~/Library/Application Support/Bobby/`.

## Run locally

Requires macOS 14 or later and Xcode or its command-line tools with Swift 5.9+.

```sh
scripts/run-app.sh
```

For a release build:

```sh
scripts/build-app.sh
open build/Bobby.app
```

The app is signed for local use on the build machine's architecture. Distribution
and notarization can come later. You can also open `Package.swift` in Xcode.

## Development

```sh
scripts/test.sh
```

Bobby uses SwiftUI around an AppKit text editor, with no third-party dependencies.
`Sources/BobbyCore` holds calculations, exchange rates, and storage.
`Sources/Bobby` holds the native app. Tests cover both the core and offscreen
editor behavior.

See [PLANS.md](PLANS.md) for direction and deferred features.
See [QA.md](QA.md) for repeatable native interaction checks.
