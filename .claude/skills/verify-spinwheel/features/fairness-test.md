# Fairness and spin length (developer)

`./test.sh` runs the wheel physics (`Physics.swift`) headlessly, with no window: thousands of random spins per team size, a chi-square test of which slice wins, and percentiles of spin time, turns and roll-back rate. Use it for any change to `Physics.swift`; it does not exercise the UI.

## Sub-features

- `fair`: every slice wins equally often for team sizes 2, 3, 4, 5, 6, 8, 10, 12.
- `length`: spin time and turns stay in the tuned range.
- `rollback`: the share of spins that end by rolling back off a peg.

## How to get to it (user POV)

- From the repo root: `./test.sh` (300 spins per size), or `./test.sh 2000` for a tighter check.

## Driving it with sw

Not driven through `sw`; it is a plain command.

- **Run.** `./test.sh 2000 | tee .verify/artifacts/fairness-$(date +%Y%m%d-%H%M%S).txt`. Exit code `0` means every size passed at p = 0.001; `1` means at least one `FAIL` line.
- **Read.** Each line: `chi²` against its `limit`, `time p10/50/90`, `turns p10/50/90`, `rollback %`. At the time of writing: about 4.5–5 s and 2.4–3 turns per spin for every size, roll-back roughly 17–44%.
- **Proof.** The saved output file and the exit code.

## Gotchas

- With 8 sizes tested at p = 0.001, a single borderline `FAIL` happens by chance about 1% of the time. Rerun with `./test.sh 2000` before concluding there is a bias.
- It shares `Physics.swift` with the app but not the display link or `Model`. Bugs in how the app steps the simulation (e.g. `b57502e`) are invisible here; compare `sim` and `wall` in the app's `spins.log` for that.
