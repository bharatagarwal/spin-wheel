# Winners sit out, Reset brings everyone back

When someone is picked their row is marked done straight away and their slice leaves the wheel at the next spin, so nobody is picked twice in a standup. Reset puts everyone back and reshuffles the slices.

## Sub-features

- `sit-out`: the winner's row reads done (struck through) as soon as the banner shows; their slice leaves the wheel when the next spin starts.
- `everyone-done`: when the last person has been picked, Spin is disabled.
- `reset`: Reset returns all names to the wheel, clears done marks and hides the banner.

## How to get to it (user POV)

- Spin, then spin again: the first winner is no longer on the wheel.
- Click **Reset** under the wheel.

## Driving it with sw

Preconditions: fresh `sw launch` with three names to keep it short: `$SW launch Ana Ben Cy`.

- **First pick.** `$SW spin` → note `winner=W1`. `$SW get member-W1` reads `done`, and their slice is still on the wheel under the flapper.
- **Sit out.** `$SW spin` → the log line reads `slices=2`, and `winner` is not W1. `$SW shot sit-out` shows two slices and W1 greyed out in the list.
- **Everyone done.** `$SW spin` → `slices=1`. `$SW press spin` now fails with `#spin is disabled`.
- **Reset.** `$SW press reset`. Every `#member-*` reads `waiting`, `$SW get winner` fails (no banner), and `$SW shot after-reset` shows all three slices.
- **Next spin after Reset.** `$SW spin` → `slices=3`, and `sim` and `wall` still agree. This guards the display-link regression, where spins after a long session ran faster than real time.
- **Proof.** `spins.log` with the slices sequence 3, 2, 1, 3; `sit-out.png`; `after-reset.png`.

## Gotchas

- The winner is crossed off when the banner appears, but their slice stays on the wheel until the next spin starts, so the flapper still points at them.
- Reset reshuffles slice order, so slice positions before and after are expected to differ.
- Reset and Spin are disabled while the wheel turns. Always `$SW wait wheel idle` (or use `sw spin`, which waits) before pressing either; a press mid-spin fails with `is disabled`, which is correct behaviour, not a bug.
