import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
from typing import NamedTuple

here = pathlib.Path(__file__).resolve().parent
spec = (here / "TurnOrder.tla").read_text()


class Mutant(NamedTuple):
    prop: str
    code_change: str
    spec_text: str
    broken_text: str


MUTANTS = [
    Mutant("PickedFromTeam", "Standup.remove(_:) loses `guard case .idle`, so × works mid-spin",
     'Remove(n) ==\n    /\\ phase = "idle"\n', 'Remove(n) ==\n'),
    Mutant("PickedOnce", "TurnOrder.beginSpin() returns `order` instead of `waiting`",
     "    /\\ wheel' = Waiting\n    /\\ slices' = Waiting\n", "    /\\ wheel' = order\n    /\\ slices' = order\n"),
    Mutant("BannerOnWheel", "Standup.remove(_:) stops clearing the banner when the winner is removed",
     "    /\\ winner' = IF winner = n THEN None ELSE winner\n", "    /\\ UNCHANGED winner\n"),
    Mutant("WheelFrozenWhileSpinning", "Standup.add(_:) calls turns.add(_:) in both phases",
     'IF phase = "idle" THEN Append(wheel, n) ELSE wheel', "Append(wheel, n)"),
    Mutant("NoDuplicateSlices", "Team.add(_:) drops its `!names.contains(name)` check",
     "    /\\ n \\notin Range(team)\n", ""),
    Mutant("NotPickedWhileHeld", "WheelSim.settle() applies the 30 s cap while .held again",
     'Stop == phase = "spinning" /\\ motion = "coasting" /\\ Finish',
     'Stop == phase = "spinning" /\\ motion \\in {"held", "coasting"} /\\ Finish'),
    Mutant("SpinsEnd",
           "WheelSim.settle() loses both the friction stop and the 30 s cap, so a coasting wheel may turn forever",
     "FairSpec == Spec /\\ UserLetsGo /\\ WheelComesToRest\n", "FairSpec == Spec /\\ UserLetsGo\n"),
    Mutant("SpinsEnd", "a held wheel never has to be let go (no release on drag end or cancel)",
     "FairSpec == Spec /\\ UserLetsGo /\\ WheelComesToRest\n", "FairSpec == Spec /\\ WheelComesToRest\n"),
]

CODE_MUTANTS = [
    Mutant("traces", "Standup.add(_:) puts a name added mid-spin on the spinning wheel",
     "case .spinning: turns.addForNextSpin(name)", "case .spinning: turns.add(name)"),
    Mutant("traces", "Standup.remove(_:) loses `guard case .idle`, so × works mid-spin",
     "guard case .idle(let winner) = phase else { return }\n        team.remove(name)",
     "let winner = winner\n        team.remove(name)"),
    Mutant("traces", "Standup.remove(_:) stops clearing the banner when the winner is removed",
     "        if winner == name { phase = .idle(winner: nil) }\n", ""),
    Mutant("traces", "Standup.reset() loses `guard case .idle`, so Reset works mid-spin",
     "guard case .idle = phase else { return }\n        turns = TurnOrder(shuffling: team.names)",
     "turns = TurnOrder(shuffling: team.names)"),
]

missed = 0
repo = here.parent
code = (repo / "Turns.swift").read_text()
for m in CODE_MUTANTS:
    if code.count(m.spec_text) != 1:
        print(f"STALE   {m.prop}: mutant text no longer matches Turns.swift; update mutants.py")
        missed += 1
        continue
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for f in ["Physics.swift", "property-test.sh"]:
            shutil.copy(repo / f, tmp)
        (tmp / "Turns.swift").write_text(code.replace(m.spec_text, m.broken_text))
        (tmp / "Tests").symlink_to(repo / "Tests")
        (tmp / ".verify").symlink_to(repo / ".verify")
        (tmp / "Verification").mkdir()
        for f in ["check.sh", "TurnOrder.tla", "TraceCheck.tla"]:
            shutil.copy(here / f, tmp / "Verification")
        r = subprocess.run(["zsh", str(tmp / "Verification/check.sh"), "traces"], capture_output=True, text=True)
        log = repo / ".verify/tla/traces.log"
        swift_log = (repo / ".verify/tla/traces-swift.log").read_text()
        by = ("TLC" if log.exists() and "Deadlock reached" in log.read_text()
              else "a contract" if "Assertion failed" in swift_log else None)
        caught = r.returncode == 1 and by is not None
        print(f"{'caught' if caught else 'MISSED'}  {m.prop}: {m.code_change}{f' (by {by})' if caught else ''}")
        missed += not caught

for m in MUTANTS:
    if spec.count(m.spec_text) != 1:
        print(f"STALE   {m.prop}: mutant text no longer matches TurnOrder.tla; update mutants.py")
        missed += 1
        continue
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy(here / "MC.tla", tmp)
        pathlib.Path(tmp, "TurnOrder.tla").write_text(spec.replace(m.spec_text, m.broken_text))
        r = subprocess.run(["zsh", str(here / "check.sh"), m.prop], capture_output=True, text=True,
                           env={**os.environ, "TURNORDER_SPEC_DIR": tmp})
        log = (here.parent / ".verify/tla" / f"{m.prop}.log").read_text()
        violation = "Temporal properties were violated" if m.prop == "SpinsEnd" else f"Invariant {m.prop} is violated"
        caught = r.returncode == 1 and violation in log
        print(f"{'caught' if caught else 'MISSED'}  {m.prop}: {m.code_change}")
        missed += not caught
sys.exit(1 if missed else 0)
