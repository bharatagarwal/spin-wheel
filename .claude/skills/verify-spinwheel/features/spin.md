# Spin and pick a winner

The user starts a spin; a physically simulated wheel turns, pegs knock the spring-hinged flapper, the wheel coasts to a stop and the slice under the flapper tip is announced in a banner.

## Sub-features

- `spin-button`: the Spin button starts a spin.
- `spin-tap`: tapping the wheel starts a spin.
- `spin-space`: the Space key starts a spin, as long as the Add name field is not focused.
- `spin-motion`: the wheel turns, the flapper deflects at pegs, the background dims and the wheel zooms in as it slows.
- `spin-result`: the banner shows the winner, which is the slice under the flapper tip.
- `spin-locked`: Spin and Reset are disabled while the wheel turns.

## How to get to it (user POV)

- Click **Spin** under the wheel.
- Click anywhere on the wheel.
- Press Space with the app frontmost.

## Driving it with sw

Preconditions: fresh `sw launch`, `sw doctor` all `ok`.

- **Before.** `$SW shot spin-before`. Five slices, no banner, every `#member-*` reads `waiting`.
- **Spin with motion capture.** `( sleep 0.3; $SW frames spin 6 0.7 ) & $SW spin; wait`. `sw spin` prints e.g. `spin slices=5 winner=Bob sim=4.92s wall=4.95s`.
- **Locked while spinning.** In a second spin, run `$SW press reset` within 1 s of `$SW press spin`; it must fail with `#reset is disabled`. Then `$SW wait wheel idle 30`.
- **Result.** `$SW get winner` equals the logged `winner=`. `$SW shot spin-after` shows the banner with that name and the flapper tip inside that name's slice.
- **Timing.** `sim` and `wall` in the log agree to within ~0.05 s, and spins take about 4–6 s.
- **Tap entry point.** `$SW press wheel` then `$SW wait wheel spinning 2`. The wheel's accessibility action calls the same `spin()` as the tap gesture.
- **Proof.** `spin-before.png`, `spin-1…6.png` (flapper bent sideways in at least one), `spin-after.png`, and `spins.log`.

## Gotchas

- The outcome is random by design. Assert that the log, the banner and the screenshot agree with each other, never a specific name.
- `#winner` is missing from the AX tree while no winner is shown (it has zero opacity). `sw get winner` fails until the first spin ends.
- SwiftUI exposes `#wheel`'s value as `AXValueDescription`; `bin/ax` reads it, but other tools reading `AXValue` see an empty string.
- Space: on launch the app clears focus from the Add name field so Space reaches Spin. Proving `spin-space` needs a real keystroke into a frontmost window (`osascript -e 'tell application "System Events" to key code 49'` after bringing our PID to the front). That steals focus from the user, so only do it when the change touches keyboard handling, and warn the user first.
- The zoom and dim are still fading out for about 1.4 s after the banner appears; shots taken immediately show them.
- Sound (peg ticks, chime) cannot be verified from here.
