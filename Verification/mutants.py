import os, pathlib, shutil, subprocess, sys, tempfile
from typing import NamedTuple

here = pathlib.Path(__file__).resolve().parent
spec = (here / "TurnOrder.tla").read_text()


class Mutant(NamedTuple):
    prop: str
    code_change: str
    spec_text: str
    broken_text: str


MUTANTS = [
    Mutant("PickedFromTeam", "Model.remove(_:) loses `guard case .idle`, so × works mid-spin",
     'Remove(n) ==\n    /\\ phase = "idle"\n', 'Remove(n) ==\n'),
    Mutant("PickedOnce", "TurnOrder.beginSpin() returns `order` instead of `waiting`",
     "    /\\ wheel' = Waiting\n    /\\ slices' = Waiting\n", "    /\\ wheel' = order\n    /\\ slices' = order\n"),
    Mutant("BannerOnWheel", "Model.remove(_:) stops clearing the banner when the winner is removed",
     "    /\\ winner' = IF winner = n THEN None ELSE winner\n", "    /\\ UNCHANGED winner\n"),
    Mutant("WheelFrozenWhileSpinning", "Model.add() calls turns.add(_:) in both phases",
     'IF phase = "idle" THEN Append(wheel, n) ELSE wheel', "Append(wheel, n)"),
    Mutant("NoDuplicateSlices", "Team.add(_:) drops its `!names.contains(name)` check",
     "    /\\ n \\notin Range(team)\n", ""),
    Mutant("NotPickedWhileHeld", "WheelSim.settle() applies the 30 s cap while .held again",
     'Stop == phase = "spinning" /\\ motion = "coasting" /\\ Finish',
     'Stop == phase = "spinning" /\\ motion \\in {"held", "coasting"} /\\ Finish'),
    Mutant("SpinsEnd", "WheelSim.settle() loses both the friction stop and the 30 s cap, so a coasting wheel may turn forever",
     "FairSpec == Spec /\\ UserLetsGo /\\ WheelComesToRest\n", "FairSpec == Spec /\\ UserLetsGo\n"),
    Mutant("SpinsEnd", "a held wheel never has to be let go (no release on drag end or cancel)",
     "FairSpec == Spec /\\ UserLetsGo /\\ WheelComesToRest\n", "FairSpec == Spec /\\ WheelComesToRest\n"),
]

missed = 0
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
