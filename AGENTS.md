# Bobby

Bobby is a personal finance scratchpad, initially intended for macOS. The main
uses are quick arithmetic, currency conversions, and small finance calculations.
It may be shared with friends later.

## Product direction

- Discuss material scope expansions before implementing them.
- Show results immediately as the user types. Do not require a trailing `=`.
- Keep ordinary notes usable alongside calculations. Recognize only complete,
  unambiguous expressions and documented finance patterns.
- Prioritize arithmetic, percentages, currency, simple interest, and Turkish
  finance terminology.
- Use English UI and English numeric formatting (`1,234.56`). Support Turkish
  finance aliases alongside English terms.
- Accept `TL` and `TRY` case-insensitively as the same currency in all currency
  inputs, including both source and destination positions. Normalize to `TRY`
  internally for exchange-rate requests.
- Accept leading-decimal literals such as `.75` as equivalent to `0.75`.
- Programmer utilities are not a priority.
- Keep source text separate from generated results.
- Keep tutorial examples and their year basis in temporary view state. Preview
  calculation must not modify scratches or trigger network work during rendering.
  Prepare missing rates separately and revisit dependent conversions when rates
  arrive. Route copy-answer to the tutorial and block background scratch commands
  while a sheet is open.
- Save scratches locally and preserve them across hides and restarts.
- Keep financial assumptions visible, including exchange-rate date and type,
  and interest day-count conventions.
- Stopaj and KDV helpers are deferred from the first release. Manual deductions
  use ordinary arithmetic. Do not silently choose statutory tax rates.
- Gold prices per gram and TCMB deposit-rate data are optional future additions,
  not requirements for the first draft.
- Simple interest uses actual elapsed days with a visible, editable 365-day year
  basis initially. Do not assume compounding.
- Number-format conventions must be explicit. Do not guess between ambiguous
  Turkish and English punctuation.

## Architecture and validation

- Build a native Swift app for macOS 14 or later, with SwiftUI for surrounding
  controls and AppKit for the editor.
- SwiftPM has no third-party dependencies. `BobbyCore` owns calculation,
  presentation, exchange rates, and persistence. `Bobby` owns the native UI.
- Run `scripts/test.sh` for tests and `scripts/build-app.sh` for a release app
  (or pass `debug`). The bundle is `build/Bobby.app`, ignored by Git.
- `scripts/run-app.sh` builds and opens a debug app. Xcode can open Package.swift.
- Build helpers keep SwiftPM/module caches inside `.build`. On restricted
  macOS sandboxes, `iconutil` needs system service access to package the icon.
- Scratch and rate data live in `~/Library/Application Support/Bobby/`.
  Unreadable scratch data must never be replaced silently.
- Percentage values are scalars (`10%` is `0.1`). Display rounding must not alter
  stored/evaluated decimals. Currency and interest show at most two decimals.
- Currency variables wait for their rate, then recalculate in source order.
- Default global shortcut: Control+Option+B. Registration uses Carbon hotkeys,
  so it does not require Accessibility permission.
- Handle Escape explicitly in the editor, since NSTextView's standard key
  binding can invoke completion. Give the editor focus after the hosting view
  is constructed, and expose result buttons through Accessibility children.
- Put space between calculation rows in paragraphSpacing, not lineSpacing.
  TextKit includes lineSpacing in populated-line caret height, producing an
  oversized insertion point compared with the empty trailing line.
- When showing the app with an attached sheet, focus the sheet's editor rather
  than the saved scratch beneath it. Restore main-editor focus after the sheet
  has detached. Activation and sheet dismissal can finish asynchronously, so
  retry focus on the main queue and use the window's end-sheet notification.
- Periodic rate refreshes must enter the main actor before updating app state.
- Use decimal arithmetic for money and rates. Round for presentation or an
  explicitly defined financial rule rather than at arbitrary intermediate steps.
- Keep the calculation engine independent from UI and network access.
- Validate financial formulas, parsing, variable recalculation, and offline rate
  behavior with meaningful tests once implementation begins.
- Use PLANS.md for milestones, major decisions, and unresolved scope questions.

## Git workflow

- The GitHub repository must be private.
- Work on `dev` or a development branch. Do not push to `main` or `master` without
  explicit user authorization.
- Make small, coherent progressive commits at meaningful milestones and push
  after each progressive commit.
- Preserve unrelated user changes.
- Run every `gh` command with `sandbox_permissions: "require_escalated"` because
  GitHub credentials are stored in macOS Keychain. Never print credentials.

## Communication

- Respond in English unless the user explicitly requests Turkish.
- Do not use em dashes in prose. Avoid semicolons unless necessary.
