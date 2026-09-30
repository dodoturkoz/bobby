# Bobby

Bobby is a personal finance scratchpad, initially intended for macOS. The main
uses are quick arithmetic, currency conversions, and small finance calculations.
It may be shared with friends later.

## Product direction

- Finish the scope discussion before substantial app implementation.
- Show results immediately as the user types. Do not require a trailing `=`.
- Keep ordinary notes usable alongside calculations. Recognize only complete,
  unambiguous expressions and documented finance patterns.
- Prioritize arithmetic, percentages, currency, simple interest, and Turkish
  finance terminology. Stopaj is an optional explicit rate in interest inputs.
- Use English UI and English numeric formatting (`1,234.56`). Support Turkish
  finance aliases alongside English terms.
- Programmer utilities are not a priority.
- Keep source text separate from generated results.
- Save scratches locally and preserve them across hides and restarts.
- Keep financial assumptions visible, including tax rates, exchange-rate date
  and type, and interest day-count conventions.
- Do not silently choose an applicable statutory tax rate. Use explicit rates or
  editable presets. Dedicated KDV helpers are deferred from the first release.
- Simple interest uses actual elapsed days with a visible, editable 365-day year
  basis initially. Do not assume compounding.
- Number-format conventions must be explicit. Do not guess between ambiguous
  Turkish and English punctuation.

## Architecture and validation

- Native Swift with SwiftUI and an AppKit editor is proposed, not yet settled.
- No application scaffold exists, so no build or test commands exist yet.
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
