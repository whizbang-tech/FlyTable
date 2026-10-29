# ADR-0001: Headless core plus custom-drawn native renderer

Status: accepted, 2026-10-29.

## Decision

FlyTable is three layers in one package: a pure-Swift headless core (columns, layout resolution,
row geometry, sort permutation, selection, cell values, cell cache); platform renderers behind the
core, the primary one a single custom-drawn view in a native scroll view that draws only visible
rows × visible columns from cached Core Text lines; and a SwiftUI API that mirrors Apple's `Table`
vocabulary. FlyUI will depend on FlyTable and supply a theme; FlyTable never depends on FlyUI.

## Why

See `../proposal.md` §4. SwiftUI `Table` and `List` gather identifiers eagerly, diff without an
opt-out and recycle nothing; `NSTableView` recycles rows but instantiates every visible column's
cell view; a custom-drawn viewport is O(visible cells) regardless of data size, which Glide Data
Grid proved on the web and NGTable on the Mac. Owning selection, keyboard, focus and accessibility
is the cost, and is paid once.

## Consequences

- Performance is measured against the acceptance table in the proposal, never asserted.
- Variable row heights are opt-in; fixed heights are the default.
- The hosted (pooled SwiftUI row) renderer and the iOS renderer are separate milestones.
- A plain `NSTableView` renderer serves as the correctness oracle in tests, never as the default.
