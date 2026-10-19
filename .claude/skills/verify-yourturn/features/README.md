# Your Turn verification map

The maintained list of user-facing journeys in Your Turn and how to prove each one with `bin/sw`. Read this index, then follow the matching feature file. When a journey fails because the app changed rather than broke, update its file in the same change.

| Feature | File | Entry points |
|---|---|---|
| Spin and pick a winner | [spin.md](spin.md) | Spin button, tap on the wheel, Space key |
| Winners sit out, Reset brings everyone back | [reset.md](reset.md) | automatic on next spin; Reset button |
| Team list | [team-list.md](team-list.md) | Add name field + Return or +; × per name |
| Fairness and spin length (developer) | [fairness-test.md](fairness-test.md) | `./test.sh` |

## Baseline preconditions

- `SW=.claude/skills/verify-yourturn/bin/sw`, run from the repo root.
- `$SW build` after the last source change, then `$SW launch` (team Alice, Bob, Charlie, Dana, Eve), then `$SW doctor` all `ok`.
- One verification instance at a time; never drive the user's `/Applications/Your Turn.app`.

## Driving conventions

- Address elements only by identifier (`#spin`, `#member-Bob`, …), never by position or coordinates.
- Every spin's outcome is random. Read the winner from the `sw spin` output or `#winner`; never hard-code an expected winner.
- Start each journey from a fresh `sw launch` unless it says otherwise, and `sw stop` at the end. Artifacts stay in `.verify/artifacts/<run-id>/`.
