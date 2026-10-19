# Fairness and spin length (developer)

`./test.sh` runs the wheel physics (`Physics.swift`) headlessly, with no window: thousands of spins per team size from 4 fixed starting angles (the app starts each spin where the last one stopped), a chi-square test of which slice wins summed over those starts, percentiles of spin time, turns and roll-back rate, and how far the flapper swings. Half the spins go anticlockwise, as a flick can. Use it for any change to `Physics.swift`; it does not exercise the UI.

## Sub-features

- `fair`: from any starting angle, every slice wins equally often, for team sizes 2, 3, 4, 5, 6, 8, 10, 12.
- `length`: p10 spin time at least 3.0 s and p90 at most 5.5 s; a line reads `LONG` and the run fails otherwise.
- `rollback`: the share of spins that end by rolling back off a peg.
- `flapper`: median peak swing of the flapper tip, split into hinge (`root`) and mid-joint `bend`.

## How to get to it (user POV)

- From the repo root: `./test.sh` (3000 spins per size), `./test.sh 1000` for a quicker check. Each run prints its seed; `./test.sh <spins> <seed>` replays it exactly.

## Driving it with sw

Not driven through `sw`; it is a plain command.

- **Run.** `./test.sh 2000 | tee .verify/artifacts/fairness-$(date +%Y%m%d-%H%M%S).txt`. Exit code `0` means every size passed at p = 0.001; `1` means at least one `FAIL` (unfair) or `LONG` (spin length out of range) line.
- **Read.** Each line: `chi²` against its `limit` (degrees of freedom 4·(slices − 1), so a fair wheel scores near that number), `time p10/50/90`, `turns p10/50/90`, `rollback %`, `flapper tip X° (root Y° + bend Z°)`. At the time of writing: about 3.4–4.9 s (p10–p90) and 1.6–3.5 turns per spin, roll-back 23–27%, flapper tip 31° (2 slices) to 40° (12 slices), 37° for 5 (root 31° + bend 12°). The user tuned the stiffness by eye to that ~37°; a change that moves it by more than a few degrees changes how the app feels.
- **Proof.** The saved output file and the exit code.

## Gotchas

- Fairness comes from how much push strength varies, not from the start angle: pushes are normally distributed (mean 10 rad/s, SD 2, cut at ±2.5 SD) so landings spread over more than a turn with soft edges. A uniform or narrow range of pushes passes a random-start test but fails this one; the parent of commit `79b43e7` has the old 9–11 rad/s range, which fails every size by 5–10×.
- With 8 sizes tested at p = 0.001, a single borderline `FAIL` happens by chance about 1% of the time. Rerun with a fresh seed before concluding there is a bias, and replay the failing seed to investigate it.
- It shares `Physics.swift` with the app but not the display link or `Model`. Bugs in how the app steps the simulation (e.g. `b57502e`) are invisible here; compare `sim` and `wall` in the app's `spins.log` for that.
