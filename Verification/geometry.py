import math
import pathlib
import re
import sys
from fractions import Fraction

from z3 import And, Or, Reals, Solver, sat, unsat

default_physics = pathlib.Path(__file__).resolve().parent.parent / "Physics.swift"
physics = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else default_physics).read_text()
radii = physics[physics.index("enum WheelRadii {"):physics.index("static func flapper(")]
swift = {"asin": math.asin, "min": min}
for name, expr in re.findall(r"static let (\w+) = (.+)", radii):
    swift[name] = eval(expr, {"__builtins__": {}}, swift)
for name in ["swingLimit", "bendLimit"]:
    swift[name] = float(re.search(rf"var {name} = ([\d.]+)", physics).group(1))

peg_circle, pivot_height = Fraction(swift["pegCircle"]), Fraction(swift["pivot"])
segment = Fraction(swift["segmentLength"])
touching = Fraction(swift["pegRadius"]) + Fraction(swift["armRadius"])
reach = Fraction(swift["flapperReach"])
window = swift["pegAngleReachableFromPointer"]
slack = Fraction(1, 10**12)

root_sin, root_cos, tip_sin, tip_cos, peg_x, peg_y, along = Reals("root_sin root_cos tip_sin tip_cos peg_x peg_y along")
arm_x, arm_y, gap_x, gap_y = Reals("arm_x arm_y gap_x gap_y")
arm_length = Fraction(swift["armLength"])
pivot = (0, -pivot_height)
joint = (pivot[0] - segment * root_sin, pivot[1] + segment * root_cos)
tip = (joint[0] - segment * tip_sin, joint[1] + segment * tip_cos)
unit_angles = [root_sin**2 + root_cos**2 == 1, tip_sin**2 + tip_cos**2 == 1]
peg_on_circle = peg_x**2 + peg_y**2 == peg_circle**2


def touches(start, end):
    closest = (start[0] + along * (end[0] - start[0]), start[1] + along * (end[1] - start[1]))
    return And(along >= 0, along <= 1, (peg_x - closest[0]) ** 2 + (peg_y - closest[1]) ** 2 <= touching**2)


flapper_touches_peg = Or(touches(pivot, joint), touches(joint, tip))


def on_segment(start, end):
    return And(along >= 0, along <= 1,
               arm_x == start[0] + along * (end[0] - start[0]), arm_y == start[1] + along * (end[1] - start[1]))


arm_point_beyond_arm_length = And(Or(on_segment(pivot, joint), on_segment(joint, tip)),
                                  arm_x**2 + (arm_y - pivot[1]) ** 2 > arm_length**2)
touching_further_than_reach = And(arm_x**2 + arm_y**2 <= arm_length**2, gap_x**2 + gap_y**2 <= touching**2,
                                  (arm_x + gap_x) ** 2 + (arm_y + gap_y) ** 2 > reach**2)
peg_near_pivot = peg_x**2 + (peg_y - pivot[1]) ** 2 <= reach**2
peg_outside_window = -peg_y < peg_circle * Fraction(math.cos(window))
flapper_at_stop = [
    root_cos >= Fraction(math.cos(swift["swingLimit"])) - slack,
    root_cos <= Fraction(math.cos(swift["swingLimit"])) + slack,
    root_cos * tip_cos + root_sin * tip_sin >= Fraction(math.cos(swift["bendLimit"])) - slack,
]


def counterexample(*facts):
    solver = Solver()
    solver.set(timeout=60000)
    solver.add(*facts)
    result = solver.check()
    if result == unsat:
        return None
    return solver.model() if result == sat else f"z3 gave up: {solver.reason_unknown()}"


claims = {
    "every point of the flapper is within armLength of the pivot": [*unit_angles, arm_point_beyond_arm_length],
    "so a peg the flapper touches is within flapperReach (armLength + armRadius + pegRadius) of the pivot":
        [touching_further_than_reach],
    f"a peg within flapperReach of the pivot is within {window:.4f} rad of the pointer, "
    "so pegsReachableFromPointer never skips a peg the flapper touches":
        [peg_on_circle, peg_near_pivot, peg_outside_window],
    f"a flapper at its stop ({swift['swingLimit']} rad), bent up to {swift['bendLimit']} rad either way, "
    "touches no peg, so the wheel never jams":
        [*unit_angles, peg_on_circle, *flapper_at_stop, flapper_touches_peg],
}
failed = 0
for claim, negation in claims.items():
    found = counterexample(*negation)
    print(f"proved  {claim}" if found is None else f"FAILED  {claim}\n  counterexample: {found}", flush=True)
    failed += found is not None
sys.exit(1 if failed else 0)
