"""Break TurnOrder.tla the way a plausible main.swift change would and expect
check.sh to catch each break. Proves that every passing property can fail.
Usage: python3 -I Verification/mutants.py"""
import os, pathlib, shutil, subprocess, sys, tempfile

here = pathlib.Path(__file__).resolve().parent
spec = (here / "TurnOrder.tla").read_text()

# (property, the main.swift change this stands for, text in TurnOrder.tla, replacement)
MUTANTS = [
    ("PickedFromTeam", "Model.remove(_:) loses `guard case .idle`, so × works mid-spin",
     'Remove(n) ==\n    /\\ phase = "idle"\n', 'Remove(n) ==\n'),
    ("PickedOnce", "TurnOrder.beginSpin() returns `order` instead of `waiting`",
     "    /\\ wheel' = Waiting\n    /\\ slices' = Waiting\n", "    /\\ wheel' = order\n    /\\ slices' = order\n"),
    ("BannerOnWheel", "Model.remove(_:) stops clearing the banner when the winner is removed",
     "    /\\ winner' = IF winner = n THEN None ELSE winner\n", "    /\\ UNCHANGED winner\n"),
    ("WheelFrozenWhileSpinning", "Model.add() calls turns.add(_:) in both phases",
     'IF phase = "idle" THEN Append(wheel, n) ELSE wheel', "Append(wheel, n)"),
    ("NoDuplicateSlices", "Team.add(_:) drops its `!names.contains(name)` check",
     "    /\\ n \\notin Range(team)\n", ""),
]

missed = 0
for prop, change, old, new in MUTANTS:
    if spec.count(old) != 1:
        print(f"STALE   {prop}: mutant text no longer matches TurnOrder.tla; update mutants.py")
        missed += 1
        continue
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy(here / "MC.tla", tmp)
        pathlib.Path(tmp, "TurnOrder.tla").write_text(spec.replace(old, new))
        r = subprocess.run(["zsh", str(here / "check.sh"), prop], capture_output=True, text=True,
                           env={**os.environ, "TURNORDER_SPEC_DIR": tmp})
        log = (here.parent / ".verify/tla" / f"{prop}.log").read_text()
        caught = r.returncode == 1 and f"Invariant {prop} is violated" in log
        print(f"{'caught' if caught else 'MISSED'}  {prop}: {change}")
        missed += not caught
sys.exit(1 if missed else 0)
