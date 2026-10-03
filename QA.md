# Validation

Run `scripts/test.sh` before committing a behavior change. The suite exercises
decimal calculations, strict numbers, source-order variables, incomplete typing,
currency names and confirmations, interest review, line edits, gesture lifecycle,
rate and gold-price presentation, offline caching, and persistence recovery. Offscreen AppKit
tests verify paging snapshots, clipping, editor handoff, cancellation, and native
Undo. Tests use deterministic quotes rather than today's changing prices.

Build with `scripts/build-app.sh` and check the native flows below. Prefer the
tutorial's separate practice editor for input checks. Preserve existing scratches.

## Currency

| Input | Expected behavior |
| --- | --- |
| `USD TL` | One-unit rate, source and observation date |
| `TL euro` | One-unit rate with up to eight decimal places |
| `3 USD to Turkish lira` | Conversion without guessing |
| `3 USD to liras` | Specific Turkish-lira confirmation, no answer before acceptance |
| `USD to lira` | Confirmation retains the one-unit rate format |
| `1,23 USD to TL` | English-number error, no fetching a rate for an invalid amount |
| `3 USD to` | Quiet while incomplete |
| `Call the bank about USD tomorrow` | Ordinary note |

Accept a currency proposal and verify only its line changes. Undo must restore
the original wording. Rate answer copying must copy a value with its currency,
and a unit rate must retain its extra precision. Hover for contributing providers
and the reference quote type. Verify cached results label offline status after a
failed refresh, without changing system network settings for routine checks.

## Gold

| Input | Expected behavior |
| --- | --- |
| `ceyrek altin` or `çeyrek altın` | Both dealer prices for one Çeyrek coin in TL |
| `2 ceyrek altin` | Both product prices multiplied by two |
| `eski ceyrek altin` | Separate Eski Çeyrek listing, no invented mint year |
| `gram altin` | Retail Gram Altın listing, distinct from other gram/bullion quotes |
| `value = gram altin sell` then `value * 2` | Scalar TRY value, dependent line recalculates after lookup |
| `value = ceyrek altin` | Ask for an explicit dealer side, no implicitly assigned price |
| `1,23 gram altin` | English-number error, no price fetch |
| `I have 2 ceyrek altin` | Ordinary note |

Check both labels explain the dealer's perspective, with full source and quote
time beneath them. Longer quantities should wrap the two prices without hiding
one side. Hover for the exact provider product, source URL, observation/retrieval
times, and Europe/Istanbul convention. Copying both prices retains their labels
and provenance. Explicit-side copy remains a scalar TL value.

Refresh from More. The app checks visible-scratch gold prices every minute,
and labels observations over 15 minutes old. Deterministic tests verify that
failed refreshes retain dated prices with a saved label, and that no-cache
failures show an unavailable result rather than a fabricated amount. Previewing
neighboring scratches must not trigger network requests. The tour's gold
practice must stay isolated from saved scratches.

## Interest review

Use `3 years interest at 42%` and `3 yıllık faiz yüzde 42'den`. Both propose
annual simple interest and require a principal. Cancel leaves the source intact.
Entering `500k` and `TL` should preview gross interest of `630,000 TL` and a final
balance of `1,130,000 TL`. Confirmation writes an explicit basis into the line.
Undo restores the original phrase. Changing the footer basis afterward must not
alter a confirmed line's basis.

Existing `500k TL %40 yıllık 32 gün` and `500k TRY at 40% for 32 days` continue
calculating directly. A reviewed assignment keeps its variable name, and its
dependent lines wait until the proposal is confirmed.

## Native interaction

- Verify tutorial practice and review never change saved scratches or their basis.
- Close a review, then type immediately to check editor focus.
- Close the tour by its Close button, Escape, a parent-window click, and an
  actual click in another app. Parent clicks should not also operate a scratch
  control. Tutorial pickers and menus remain usable.
- While a review is open, scratch creation/navigation/export and answer-copy
  commands must not operate the underlying saved scratch.
- With at least two existing scratches, swipe left/right over the main editor.
  Text and answers should follow the fingers, with the adjacent scratch sliding
  into view. The header, footer, and sidebar should stay still. Release past the
  threshold to change one scratch. Short or cancelled swipes settle back without
  changing text, selection, or Undo. Reversing direction should preview the other
  neighbor. At the first and last scratch, movement should resist and settle back.
  Vertical, diagonal, and momentum gestures must not trigger extra navigation.
  Editing, resizing, losing focus, or opening a sheet should safely cancel a
  pending slide. Reduce Motion should switch directly on release. Check physical
  direction and animation feel with a real trackpad.
- Check button and keyboard navigation, autosave, relaunch restoration, the
  configured global shortcut, and Escape hide/show after editor changes.

UI automation may emit an additional foreign-app click after an accessibility
button action. Such a click intentionally dismisses the tutorial. Confirm that
case with window-event logs or a physical click, rather than changing production
dismissal behavior to accommodate synthetic input.
