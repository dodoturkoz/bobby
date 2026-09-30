# Bobby: scope and implementation plan

## Direction

A fast scratchpad for quick maths, currency, and small personal finance
calculations. Turkish finance terminology and useful local conventions are part
of the intended experience. The first audience is the owner, with possible
distribution to friends later.

Status: first-release scope, input conventions, and native architecture are
agreed. Repository setup and planning are complete. Application implementation
has not started.

## Agreed decisions

- Working name: Bobby.
- Priorities: quick maths, currency, and simple finance calculations.
- Results appear immediately without a trailing evaluation marker.
- Programmer utilities can be omitted.
- Initialize Git, create a private GitHub repository, and maintain this plan.
- Make progressive commits on a development branch and push after every commit.
- English UI and numeric formatting (`1,234.56`).
- Turkish finance aliases alongside English terms.
- `TL` and `TRY` are interchangeable, case-insensitive currency inputs, whether
  used as the source or destination. Normalize to `TRY` internally.
- Accept leading decimals such as `.75` for ordinary arithmetic.
- Simple interest with actual elapsed days and a visible, editable 365-day year
  basis initially.
- Omit stopaj and dedicated tax helpers from the first release. Manual
  deductions use ordinary arithmetic.
- Gold prices per gram and TCMB deposit-rate data are useful candidates for
  later additions, not requirements for the first draft.
- Native Swift macOS app targeting macOS 14 or later, with SwiftUI surrounding
  an AppKit editor.

## Proposed first release

1. Instant scratchpad: global shortcut, floating window, hide/show, independent
   scratches, local autosave and recovery, copy results, text/Markdown export.
2. Arithmetic: parentheses, percentages, powers, number shorthand, and variables
   scoped to a scratch and evaluated from top to bottom.
3. Currency: explicit currency codes, interchangeable case-insensitive TL/TRY
   aliases, cached reference rates, source and observation date, and visible
   stale/offline state.
4. Simple interest: principal, annual rate, duration, visible day-count basis,
   gross interest, and final balance before any deductions.

Accepted input examples:

```text
11.5m * 2%
500 USD to TL
500 tl to usd
500k TL %40 yıllık 32 gün
```

Manual adjustments use ordinary arithmetic and can reference an earlier
variable, for example `interest * .75`. Leading decimal `.75` is equivalent to
`0.75`. The interest helper itself shows gross interest and the final balance
before any deductions.

## Technical direction

- Native macOS 14+ app in Swift.
- SwiftUI for surrounding controls and AppKit for the text editor.
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

## Implementation decisions to document

- Define the small grammar around the accepted input examples, including
  completeness detection, ordered variables, and percentage semantics.
- Use the candidate reference-rate service initially with explicit pair inputs.
  Do not substitute bank buy/sell prices silently.
- Choose result placement and minimal visual treatment while retaining plain
  editable source text.
- Keep the agreed English punctuation rules consistent across every helper.

## Milestones

1. Completed: settle scope, input conventions, and native architecture, and
   record the agreed contract here.
2. Build the native editor shell with local saving and keyboard behavior.
3. Add and test arithmetic, ordered variables, and live result presentation.
4. Add and test simple interest with visible assumptions.
5. Add exchange-rate fetching, caching, attribution, and offline behavior.
6. Use Bobby for real daily calculations, address friction, and package a local
   app. Discuss signing and distribution when sharing becomes relevant.

## Deferred features

Programmer utilities, general unit conversion, broad natural-language parsing,
loan amortization, portfolio tracking, automatic statutory tax classification,
date/time utilities, networking, AI, rich math rendering, accounts, sync, and
direct integrations with other note-taking apps.

Stopaj, dedicated KDV helpers, and broader Turkish finance conveniences can be
considered later. Product/category-specific rate selection is outside the initial
scope. Compounding is also deferred initially.

Future reference-data candidates:

- Gold price per gram in TL: settle the source, purity, quote type (buy, sell, or
  reference), and observation timestamp before integrating a feed.
- TCMB deposit-interest data: settle the relevant series, currency, term, and
  observation dates before integrating it. Treat these sector averages as dated
  benchmarks, not individual bank offers. TCMB's methodology annualizes and
  compounds rates, so do not silently insert them into the simple-interest
  calculator without an explicit conversion/convention.

Neither data feed is required for the first draft.

## Background sources

- [Frankfurter documentation](https://frankfurter.dev/): candidate currency
  service, provider filtering, attribution, and rate semantics.
- [GIB 2026 temporary Article 67 guide](https://cdn.gib.gov.tr/api/gibportal-file/file/getFile?objectKey=DUYURU%2FUNIVERSAL%2F2026%2F2026_Gecici67.pdf):
  background showing that withholding treatment depends on context and dates.
  This is not an automatically maintained source of current rates.
- [TCMB weekly deposit-interest data](https://www.tcmb.gov.tr/wps/wcm/connect/TR/TCMB%2BTR/Main%2BMenu/Istatistikler/Faiz%2BIstatistikleri/Haftalik/Mevduat%2BFaiz%2BOranlari/)
  and [methodology](https://www.tcmb.gov.tr/wps/wcm/connect/c1731b0f-de47-46ad-92c5-cc2c3d2942d3/RIPMetaveri-1_Haftal%C4%B1k_Mevduat_Ag%C4%B1rl%C4%B1kl%C4%B1_Ortalama_Faiz.pdf?MOD=AJPERES):
  candidate later benchmark source and rate conventions.
