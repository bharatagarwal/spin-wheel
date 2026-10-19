---
name: verify-yourturn
description: Launch and drive the Your Turn macOS app (SwiftUI standup picker in this repo) through the accessibility API to prove behaviour - spinning and picking a winner, editing the team list, Reset - with screenshots and a per-spin log as evidence. Use whenever you change main.swift or Physics.swift and need to confirm the change in the real app, or when asked to run, screenshot or verify the app.
---

# Verify Your Turn

Your Turn is a single-window SwiftUI macOS app (`main.swift`, `Physics.swift`, built by `./build.sh` into `YourTurn.app`). There is no server, no CLI surface and no web UI: the user touches one window. You drive it with `bin/sw`, which builds an isolated copy of the app, launches it, and presses controls by **accessibility identifier** through a small AX tool (`bin/ax.swift`, compiled by `sw build`).

All commands below run from the repo root. `sw` is `.claude/skills/verify-yourturn/bin/sw`:

```sh
SW=.claude/skills/verify-yourturn/bin/sw
```

The feature map in `features/` is the maintained list of user journeys. Read `features/README.md` before proving a change, and drive every entry point the relevant feature file lists.

## Isolation: what makes this safe

- `sw build` copies the app to `.verify/YourTurnVerify.app` with bundle id `local.spinwheel.verify`, so it has its **own UserDefaults**. The user's real team list lives under `local.spinwheel` and is never read or written.
- Driving is by AX actions on our own PID, not keystrokes or clicks, so it does not need the window to be frontmost and does not type into whatever the user has focused. It can run alongside the user's own copy of the app.
- Only one verification instance at a time: `sw launch` refuses if one is already running. Do not drive the user's `/Applications/Your Turn.app` or a copy you did not launch.

## Launch

```sh
$SW build                          # ./build.sh + verify copy + ax tool (~30 s)
$SW launch                         # team: Alice Bob Charlie Dana Eve
$SW launch Ana Ben Cy              # or any team, one argument per name
```

`launch` resets the verify domain, seeds `names`, starts the app through `open -n` (LaunchServices; running the binary directly can leave it without a window) with `YOURTURN_VERIFY_LOG` pointing at the run's artifact dir, and waits until the `#spin` button is reachable over AX. Ready output:

```
ready pid=68166 run=20261019-161558 artifacts=/…/spin-wheel/.verify/artifacts/20261019-161558
```

Rebuild with `sw build` after every source change; `sw doctor` flags a stale build.

## Doctor

Run first, and again whenever anything looks off:

```sh
$SW doctor
```

All lines must read `ok`: instance running, process is our verify build, bundle id `local.spinwheel.verify`, build newer than `main.swift` and `Physics.swift`, `#spin` reachable over AX, window on screen. It also prints the seeded names and the artifact dir. If AX fails with "accessibility permission missing", the terminal running you needs Accessibility permission in System Settings → Privacy & Security; ask the user, you cannot grant it.

## Drive

Elements are addressed by accessibility identifier. `sw tree` prints the live window tree (windows only):

| Identifier | Element | Readable value |
|---|---|---|
| `#wheel` | the wheel (tap = spin) | `spinning` / `idle` |
| `#winner` | winner banner over the wheel | the winner's name; absent from the tree while no winner is shown |
| `#spin`, `#reset` | buttons | disabled while spinning (press fails with "is disabled") |
| `#member-<name>` | a name in the team list | `waiting` / `done` |
| `#remove-<name>` | its × button | |
| `#name-field`, `#add` | add-name field and + button | field text |

Commands:

```sh
$SW spin                 # press #spin, wait for #wheel spinning → idle, print the logged result line
$SW press reset          # press any element by identifier
$SW get winner           # read an element's value
$SW wait wheel idle 30   # block until an element reads a value
$SW add Frank            # set #name-field, press #add
$SW names                # the persisted team list (UserDefaults of the verify copy)
$SW tree                 # dump the window's AX tree
```

`sw spin` prints the line the app appended to `spins.log`, e.g. `spin slices=5 winner=Bob sim=4.92s wall=4.95s`. `sim` is simulated time, `wall` is real time; they must agree to within a few hundredths of a second. A `wall` much shorter than `sim` means the physics is being stepped more than once per frame (the display-link bug fixed in `b57502e`).

## Evidence

Everything goes in `.verify/artifacts/<run-id>/` (gitignored), which `sw stop` never deletes:

- `spins.log`: one line per finished spin from the app itself (slices, winner, sim and wall time).
- `app.stderr`: the app's stderr.
- `sw shot <name>`: window screenshot → `<name>.png`. `sw frames <name> <n> <seconds>`: a timed series → `<name>-1.png`… (run it in the background during a spin to capture motion).

Proof standards:

- Go through the user's controls (`#spin`, `#add`, `#remove-*`, `#reset`). Never set model state directly or add test-only hooks to force an outcome.
- Capture the action and the resulting state: a before shot, frames during, an after shot, and the AX values (`#winner`, `#member-*`).
- Check side effects, not just pixels: the `spins.log` line for each spin, and `sw names` for anything that should persist.
- Cross-check channels against each other: the logged winner must equal `#winner` and the slice under the flapper tip in the after shot.
- Sound cannot be observed from here. Say so rather than claiming it works.

## Cleanup

```sh
$SW stop
```

Kills only the PID that `sw launch` recorded, deletes the `local.spinwheel.verify` defaults, and removes `.verify/state/`. It keeps `.verify/artifacts/` and `.verify/YourTurnVerify.app` (rebuilt by the next `sw build`). Run it after every attempt, including failed ones, before launching again. Never `pkill YourTurn`: that would also kill the user's own copy.

## Helpers

- `bin/sw`: the harness above; `sw help` lists every command.
- `bin/ax.swift`: the AX driver, compiled to `.verify/bin/ax` by `sw build`. Direct use: `.verify/bin/ax <pid> tree|press <id>|get <id>|set <id> <text>|wait <id> <value> [s]|window-id`.

## Not covered by this harness

- Physics fairness and spin-length statistics come from `./test.sh` (headless, no UI); see `features/fairness-test.md`.
- Keyboard Space-to-spin needs a real keystroke into a frontmost window; see `features/spin.md` for how and when to do that.
