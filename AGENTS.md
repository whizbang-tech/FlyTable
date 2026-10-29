# FlyTable

Public repository under `whizbang-tech`. Keep it free of FlyUI, Amicus, client data and private
workspace paths: synthetic data only, and the FlyUI dependency runs FlyUI → FlyTable, never the
reverse. Follow the Foundry workspace `AGENTS.md`, `TESTING.md` and `AUTONOMY.md` when working
from that workspace; track work on the Foundry Board only.

- `Sources/FlyTableCore` is pure Swift and fully unit-tested; every behaviour there needs a test
  in `Tests/FlyTableCoreTests` (Swift Testing).
- `Sources/FlyTable` holds the SwiftUI API and the platform renderers under `macOS/`. The renderer
  draws from the core's resolved layout and geometry; it never duplicates that logic.
- `docs/proposal.md` is the plan of record; `docs/decisions/` holds the ADRs; `docs/research/`
  holds the evidence. Update the proposal's milestone table when a milestone lands.
- Run `swift build` and `swift test` before every commit; run the gallery (`swift run
  FlyTableGallery`) for any renderer change and look at it.
- Performance claims are measured, never asserted: the benchmark target and the acceptance table
  in `docs/proposal.md` §5.4 are the bar.
