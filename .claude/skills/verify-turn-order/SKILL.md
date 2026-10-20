---
name: verify-turn-order
description: Model-check who Hot Potato calls on - the round phase, turn order and spin motion in Turns.swift and Session.swift (Team, TurnOrder, SpinSession, Model) plus WheelSim's stop rules - with TLA+/TLC over every order of spins, drags, releases, adds, removes and resets. Use whenever a change touches those types or WheelSim.Phase/settle(), or when asked whether someone can be picked twice, picked after removal, or picked while holding the wheel.
---

# Verify turn order

`Verification/TurnOrder.tla` is a small model of how Hot Potato decides who is called on. TLC explores every order of user actions and spin endings for a team drawn from four names, and checks the properties below in every reachable state. Tests and `sw` runs only try the orders someone thought of; this tries all of them.

## What it proves

Each property: the promise, then what the user would see if it broke.

| Property | Promise | Harm if broken |
|---|---|---|
| `PickedFromTeam` | The person called on is on the team at that moment. | Someone removed mid-standup gets called on. |
| `PickedOnce` | Nobody is called on twice before Reset. | A person speaks twice; someone else is skipped. |
| `BannerOnWheel` | The banner's name is a slice on the wheel. | The banner names someone the flapper isn't pointing at. |
| `WheelFrozenWhileSpinning` | While the wheel turns, the slices drawn are the slices simulated. | The wheel redraws as it stops and the flapper points at the wrong name (this happened with a mid-spin add before `706a41e`'s fix). |
| `NoDuplicateSlices` | No name has two slices. | One person gets double odds. |
| `NotPickedWhileHeld` | A spin is decided only after the user lets go. | Holding the wheel chooses the winner. |

## Findings

- None open.
- Fixed: a wheel held for 30 s used to be decided while held. `WheelSim.settle()` applied its 30 s safety cap in every phase, so holding the wheel picked the slice under the flapper. The next `Model.drag` then started a new spin. The cap now counts from `push(_:)` and is skipped while `.held`. `NotPickedWhileHeld` guards this, and `mutants.py` brings the old behaviour back to prove it still fails.
- When a property fails on code you didn't mean to change, report it here as a finding. To record it as known while it is unfixed, add it to `KNOWN_FINDINGS` in `check.sh`; the check then expects it to fail and says `FIXED?` when it stops failing.

## Does my change need this?

Check whether your change touches the covered code since the sync commit:

```sh
git diff 3967681 -- Turns.swift Session.swift main.swift Physics.swift
```

Covered code. If your diff touches any of it, run the check, and re-read the matching model action:

| Code | Model action in `TurnOrder.tla` |
|---|---|
| `Model.spin()`, `Model.begin()`, `TurnOrder.beginSpin()`, `TurnOrder.waiting` | `Spin`, `Begin`, `Waiting` |
| `Model.drag(to:at:)` (idle branch), `SpinSession.grab(at:)` | `Grab` |
| `Model.release()`, `SpinSession.release(using:)` | `Release` |
| `SpinSession.frame(_:)` stop branch, `Model.finish(_:)`, `TurnOrder.markDone(_:)` | `Stop`, `Finish` |
| `WheelSim.Phase`, `WheelSim.settle()` (settling and the 30 s cap from `releasedAt`), `WheelSim.stepWheel` `.held` case, `WheelSim.drive(_:)` | `Stop` is enabled only while `motion = "coasting"`: a held wheel never stops |
| `Model.add()`, `Team.add(_:)`, `TurnOrder.add(_:)`, `TurnOrder.addForNextSpin(_:)` | `Add` |
| `Model.remove(_:)`, `Team.remove(_:)`, `TurnOrder.remove(_:)` | `Remove` |
| `Model.reset()`, `TurnOrder.init(shuffling:)`, `ContentView.onAppear` | `Reset`, `Init` |
| `Model.Phase`, `Model.winner`, `SpinSession.Motion` | variables `phase`, `winner`, `motion` |

Variables:

| Variable | Swift |
|---|---|
| `team` | `Team.names` |
| `order` | `TurnOrder.order` (Reset keeps team order instead of shuffling) |
| `done` | `TurnOrder.done` |
| `wheel` | `TurnOrder.wheel`, the slices drawn |
| `phase` | `Model.phase`: `"idle"` or `"spinning"` |
| `winner` | the name in `Model.Phase.idle(winner:)`, or `None` |
| `slices` | `SpinSession.slices` of the running session, `<<>>` when idle |
| `motion` | `SpinSession.motion`: `"held"`, `"coasting"`, or `"none"` when there is no session (`.finished` is never observed because `Model.finish(_:)` drops the session in the same frame) |
| `pickRecordForProperties` | nothing in Swift: what the last `Finish` picked and in what state, so the properties can inspect it |

Each action is one Model method or one display-link frame. They are atomic because SwiftUI actions and the `CADisplayLink` callback run one at a time on the main thread.

Physics changes that only move *where* the wheel stops (forces, friction, geometry) are not covered here; use `./test.sh` (see the `verify-hotpotato` skill's `features/fairness-test.md`).

## Run it

From the repo root. `./check.sh` runs these along with every other check in the repo (build, lint, complexity, unit tests, property-based tests, physics statistics); `./check.sh quick` skips the statistics.

```sh
Verification/check.sh                 # all properties, about 5 s
Verification/check.sh PickedOnce      # one property
python3 -I Verification/mutants.py    # proves each passing property can still fail, about 5 s
```

The first run downloads TLC v1.7.4 (`tla2tools.jar`, SHA-256 pinned in `check.sh`) into `.verify/tools/`. It needs Java 11 or later; `java -version` should work. Logs and traces go to `.verify/tla/<Property>.log` (gitignored).

Output lines:

- `pass   P  N distinct states found`: holds in all N reachable states (currently 10,149).
- `FAIL   P` plus `trace: …log`: violated; read the trace (below). Exit code 1.
- `known  P (still fails, as recorded)`: a finding listed in `KNOWN_FINDINGS` (none at the moment).
- `FIXED? P now passes`: a known finding stopped failing; confirm the fix and update `KNOWN_FINDINGS` and Findings. Exit code 1.
- `TLC did not finish cleanly`: a parse or config error, not a verdict. Exit code 2.

`mutants.py` prints `caught` for each mutant. `MISSED` means a property can no longer fail, so the model has drifted. `STALE` means a mutant's text no longer matches the spec, so update `MUTANTS` to break the same thing in the new text.

## Reading a failure

In the log, each `State n: <Action …>` is one step, and the table above maps it to code. Retell it as steps in the app ("Ben is removed, the user grabs the wheel, the spin times out while held, Ben is called on"). Then decide which kind of failure it is:

- **Real bug.** Every step is something the code allows: find the guard in the Swift that should have blocked it and doesn't. Report it with the steps. Do not weaken the property or the model to make it pass, and don't change product code unless the user asks.
- **Modeling error.** A step is something the code cannot do, for example the model lets `Remove` run while spinning but `Model.remove(_:)` guards on `.idle`. Fix the action in `TurnOrder.tla` to match the code, then rerun `check.sh` and `mutants.py`.

## Updating the model for an intended change

1. Change the matching action so it does exactly what the new Swift does. One Model method or one display-link frame is one action. All of them run on the main thread, which is why each is atomic.
2. If the change adds state the properties depend on, add a variable and a row for it in the Variables table above.
3. Run `Verification/check.sh` and `python3 -I Verification/mutants.py`. Add a mutant for any new property.
4. Update the code-to-action table and, once you've confirmed that the model matches the code at your commit, move the sync commit below forward.

## Scope and assumptions

- **Bounds:** names come from {Ana, Ben, Cy, Dee}, and the team starts as Ana, Ben, Cy (`MC.tla`). Each name can be added and removed any number of times. Bugs that need five or more distinct names are out of reach. Nothing in the code depends on team size, so that is unlikely to matter.
- **Not modelled:**
  - Where the wheel lands. `Finish` may pick any slice. Fairness is `./test.sh`'s job.
  - Shuffling. `Reset` keeps team order, and no property depends on order.
  - Persistence. `Team.load()` and `save()` are not modelled.
  - Sound and the accessibility layer.
  - UI-level `.disabled` modifiers. The model gives only the Model's own guards credit, so anything reachable through AX or the keyboard is covered.
- **Atomicity assumption:** SwiftUI actions and the `CADisplayLink` callback run one at a time on the main thread. If any of them move off the main actor, this model no longer describes the code.
- **A pass covers this model at these bounds**, not the whole app.

## Coverage record

- Files: `Turns.swift` (`Team`, `TurnOrder`), `Session.swift` (`SpinSession`, `Model`), `main.swift` (`ContentView.onAppear`) and `Physics.swift` (`WheelSim.Phase`, `push`, `drive`, `settle` with its 30 s cap from `releasedAt`, and the `.held` case of `stepWheel`).
- **Sync commit: `3967681`.** The model was last confirmed to describe the covered code at this commit. Move it forward only after re-reading the covered code at the new commit against the table above and running both commands.
