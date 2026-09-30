# Bobby

A native macOS 14+ personal finance scratchpad for quick maths, currency
conversions, and simple interest, with results that appear as you type.

Bobby uses SwiftUI around a continuous AppKit plain-text editor. It accepts TL
and TRY interchangeably, uses English UI and number formatting, and supports
English and Turkish finance input. It has no third-party dependencies.

## Run locally

Install Xcode or its command-line tools with Swift 5.9 or later, then run:

```sh
scripts/run-app.sh
```

For a release build:

```sh
scripts/build-app.sh
open build/Bobby.app
```

The generated app is ad-hoc signed for local use on the build machine's
architecture. Public distribution and notarization are outside this first draft.
You can also open `Package.swift` in Xcode.

## Examples

```text
11.5m * 2%
0.1 + 0.2
rent = 25000
rent * 12
500 USD to TL
500 tl to usd
interest = 500k TL %40 yıllık 32 gün
interest * .75
500k TRY at 40% for 32 days
```

Results appear alongside source text. Click an answer to copy it and hover for
details. Variables apply to later lines in the same scratch and recalculate when
you change their definition. Currency variables recalculate after rates arrive.

Numbers use English punctuation (`1,234.56`), `k`/`m` shorthand, and leading
decimals such as `.75`. Percentages are ordinary scalars, so `10%` means `0.1`.
Powers use integer exponents. Plain notes and incomplete expressions stay quiet.

Interest is simple, using elapsed days and the visible year basis (365 by
default). The footer offers 360/365/366, and an input may end with `basis 360`.
The result shows gross interest and the final balance before deductions.

Currency answers use Frankfurter's dated blended reference rates. Hover to see
the rate, source, and date. Previously fetched quotes remain available offline.
Refresh rates from the More menu.

## Tutorial

Choose **Take a tour** in the header or menu to open six short lessons covering
maths, variables, currency, simple interest, scratches, and shortcuts. The first
four include editable examples with live answers and reset controls. Currency
practice supports rate refresh, and interest practice has its own year picker.
Tutorial examples and settings do not change your saved scratches. Escape
or a click outside closes the tutorial. The labeled Close button is also
available, and Command+Shift+C copies the selected practice answer.

## Keyboard and storage

- `Control+Option+B`: show or hide Bobby from any app, configurable in Settings.
- `Escape`: hide the scratchpad.
- `Command+N`: new scratch.
- `Command+Shift+C`: copy the answer on the current line.
- `Command+Option+Left/Right`: previous/next scratch.
- `Command+Shift+S`: export source text. Markdown export is in the More menu.

Scratches autosave locally, survive restarts, and are deleted only when you
choose to delete them. Data is in `~/Library/Application Support/Bobby/`.
Unreadable scratch files are preserved and saving pauses so you can export
new work. No account or cloud sync is involved.

## Development

```sh
scripts/test.sh
```

`Sources/BobbyCore` contains the deterministic decimal engine, result
presentation, versioned persistence, and asynchronous exchange-rate cache.
`Sources/Bobby` contains the native editor, window, shortcut, and app model.

See [PLANS.md](PLANS.md) for direction and deferred features.
