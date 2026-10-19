# Team list

The panel on the right lists the team. The user adds a name in the field at the bottom and removes one with its ×. The list persists across launches in UserDefaults (`names`, newline-separated).

## Sub-features

- `add`: typing a name and pressing Return or + adds it to the list and the wheel.
- `add-reject`: blank names and duplicates are ignored.
- `remove`: × removes a name from the list and the wheel.
- `persist`: the list survives quitting and relaunching.

## How to get to it (user POV)

- Click **Add name**, type, press Return or click **+**.
- Click **×** next to a name.

## Driving it with sw

Preconditions: fresh `sw launch` (Alice, Bob, Charlie, Dana, Eve).

- **Add.** `$SW add Frank`. `$SW get member-Frank` reads `waiting`; `$SW names` ends with `Frank`; `$SW shot added` shows six slices including Frank.
- **Reject duplicate.** `$SW add Frank` again. `$SW names` still lists Frank once.
- **Reject blank.** `$SW add " "`. `$SW names` is unchanged.
- **Remove.** `$SW press remove-Bob`. `$SW get member-Bob` fails (no element); `$SW names` has no Bob; `$SW shot removed` shows five slices without Bob.
- **Persist.** Run the app's own relaunch: `kill $(cat .verify/state/pid)`, start it again with `open -n .verify/YourTurnVerify.app`, write `pgrep -n -f YourTurnVerify.app/Contents/MacOS/YourTurn` into `.verify/state/pid`, and `$SW wait spin ""` to wait for the window. `$SW names` and the tree must show the list from before (with Frank, without Bob). Do not use `sw launch` for this step: it reseeds the list.
- **Proof.** `added.png`, `removed.png`, and the `sw names` output before and after relaunch.

## Gotchas

- `sw add` sets the field's value over AX and then presses +. Return-to-submit needs a real keystroke into a frontmost window; only prove it when the change touches the field's submit handling.
- Removing a name mid-spin does not take it off the turning wheel; it takes effect after the spin.
- Names are trimmed of spaces before the duplicate check.
