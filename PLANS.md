# Bobby: scope and implementation plan

## Direction

A fast scratchpad for quick maths, currency, and small personal finance
calculations. Turkish finance terminology and useful local conventions are part
of the intended experience. The first audience is the owner, with possible
distribution to friends later.

Status: the product scope and input conventions are settled enough for a first
version. Repository setup and planning are authorized. The native architecture
choice is awaiting confirmation before substantial application implementation.

## Agreed decisions

- Working name: Bobby.
- Priorities: quick maths, currency, and simple finance calculations.
- Results appear immediately without a trailing evaluation marker.
- Programmer utilities can be omitted.
- Initialize Git, create a private GitHub repository, and maintain this plan.
- Make progressive commits on a development branch and push after every commit.
- English UI and numeric formatting (`1,234.56`).
- Turkish finance aliases alongside English terms.
- Simple interest with actual elapsed days and a visible, editable 365-day year
  basis initially.
- Explicit tax rates or editable presets, with no automatic legal-rate choice.
- Dedicated tax helpers are optional later additions, not first-release goals.

## Proposed first release

1. Instant scratchpad: global shortcut, floating window, hide/show, independent
   scratches, local autosave and recovery, copy results, text/Markdown export.
2. Arithmetic: parentheses, percentages, powers, number shorthand, and variables
   scoped to a scratch and evaluated from top to bottom.
3. Currency: explicit currency codes and TL/TRY aliases, cached reference rates,
   source and observation date, visible stale/offline state.
4. Simple interest: principal, annual rate, duration, visible day-count basis,
   optional withholding, gross interest, withholding amount, net interest, and
   final balance.

Accepted input examples:

```text
11.5m * 2%
500 USD to TRY
500k TL %40 yıllık 32 gün stopaj %15
```

The stopaj percentage above is an illustrative user-supplied assumption, not a
statutory default. The interest helper shows gross interest, withholding, net
interest, and final balance.

## Proposed technical direction

- Native macOS app in Swift.
- SwiftUI for surrounding controls and AppKit for the text editor if needed.
- A deterministic parser/evaluator, independent of the UI and network. Start
  with arithmetic and a small documented grammar for finance helpers.
- Complete recognized lines get live results beside the editable text.
  Ordinary prose remains plain text. Incomplete input should not produce noisy
  errors while the user is typing.
- Decimal arithmetic for financial values, with defined rounding behavior.
- Simple versioned local persistence initially. Choose a database only if the
  actual storage requirements justify it.
- Frankfurter v2 is the candidate exchange-rate service. It supplies reference
  rates, not a promise of a particular bank's executable buy/sell quote.
- English UI and numeric formatting with English/Turkish finance aliases.

## Decisions to settle before implementation

- Confirm native macOS in Swift. Recommended minimum: macOS 14.

## Implementation decisions to document

- Define the small grammar around the accepted input examples, including
  completeness detection, ordered variables, and percentage semantics.
- Use the candidate reference-rate service initially with explicit pair inputs.
  Do not substitute bank buy/sell prices silently.
- Choose result placement and minimal visual treatment while retaining plain
  editable source text.
- Keep the agreed English punctuation rules consistent across every helper.

## Milestones

1. Settle scope and input conventions, then record the agreed contract here.
2. Build the native editor shell with local saving and keyboard behavior.
3. Add and test arithmetic, ordered variables, and live result presentation.
4. Add and test simple interest and optional withholding with visible
   assumptions.
5. Add exchange-rate fetching, caching, attribution, and offline behavior.
6. Use Bobby for real daily calculations, address friction, and package a local
   app. Discuss signing and distribution when sharing becomes relevant.

## Deferred features

Programmer utilities, general unit conversion, broad natural-language parsing,
loan amortization, portfolio tracking, automatic statutory tax classification,
date/time utilities, networking, AI, rich math rendering, accounts, sync, and
direct integrations with other note-taking apps.

Dedicated KDV helpers and broader Turkish finance conveniences can be added
later using explicit rates. Product/category-specific rate selection is outside
the initial scope. Compounding is also deferred initially.

## Background sources

- [Frankfurter documentation](https://frankfurter.dev/): candidate currency
  service, provider filtering, attribution, and rate semantics.
- [GIB 2026 temporary Article 67 guide](https://cdn.gib.gov.tr/api/gibportal-file/file/getFile?objectKey=DUYURU%2FUNIVERSAL%2F2026%2F2026_Gecici67.pdf):
  background showing that withholding treatment depends on context and dates.
  This is not an automatically maintained source of current rates.
