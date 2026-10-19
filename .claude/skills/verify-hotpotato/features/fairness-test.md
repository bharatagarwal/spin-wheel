# Fairness and spin length (developer)

`./test.sh` runs the wheel physics (`Physics.swift`) headlessly, with no window: thousands of random spins per team size, a chi-square test of which slice wins, percentiles of spin time, turns and roll-back rate, and how far the flapper swings. Half the spins go anticlockwise, as a flick can. Use it for any change to `Physics.swift`; it does not exercise the UI.

## Sub-features

- `fair`: every slice wins equally often for team sizes 2, 3, 4, 5, 6, 8, 10, 12.
- `length`: spin time and turns stay in the tuned range.
- `rollback`: the share of spins that end by rolling back off a peg.
- `flapper`: median peak swing of the flapper tip, split into hinge (`root`) and mid-joint `bend`.

## How to get to it (user POV)

- From the repo root: `./test.sh` (3000 spins per size), `./test.sh 1000` for a quicker check. Each run prints its seed; `./test.sh <spins> <seed>` replays it exactly.

## Driving it with sw

Not driven through `sw`; it is a plain command.

- **Run.** `./test.sh 2000 | tee .verify/artifacts/fairness-$(date +%Y%m%d-%H%M%S).txt`. Exit code `0` means every size passed at p = 0.001; `1` means at least one `FAIL` line.
- **Read.** Each line: `chi²` against its `limit`, `time p10/50/90`, `turns p10/50/90`, `rollback %`, `flapper tip X° (root Y° + bend Z°)`. At the time of writing: about 4.1–4.3 s and ~2.5 turns per spin, roll-back 23–27%, flapper tip 31° (2 slices) to 40° (12 slices), 37° for 5 (root 31° + bend 12°). The user tuned the stiffness by eye to that ~37°; a change that moves it by more than a few degrees changes how the app feels.
- **Proof.** The saved output file and the exit code.

## Gotchas

- With 8 sizes tested at p = 0.001, a single borderline `FAIL` happens by chance about 1% of the time. Rerun with a fresh seed before concluding there is a bias, and replay the failing seed to investigate it.
- It shares `Physics.swift` with the app but not the display link or `Model`. Bugs in how the app steps the simulation (e.g. `b57502e`) are invisible here; compare `sim` and `wall` in the app's `spins.log` for that.
