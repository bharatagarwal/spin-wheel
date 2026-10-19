#!/bin/zsh
# Model-check TurnOrder.tla, one property per TLC run.
# Usage: Verification/check.sh [property...]   (default: all)
# Exit 0 when every property passes except the known findings, which must still fail.
set -e
HERE=${0:A:h}
SPEC_DIR=${TURNORDER_SPEC_DIR:-$HERE}    # mutants.py points this at a broken copy
TLC_VERSION=v1.7.4
TLC_SHA256=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
JAR=${HERE:h}/.verify/tools/tla2tools-$TLC_VERSION.jar
if [[ ! -f $JAR ]]; then
    mkdir -p ${JAR:h}
    curl -sSL -o $JAR https://github.com/tlaplus/tlaplus/releases/download/$TLC_VERSION/tla2tools.jar
fi
[[ $(shasum -a 256 $JAR | cut -d' ' -f1) == $TLC_SHA256 ]] || { print "tla2tools.jar checksum mismatch"; exit 2 }

ALL=(PickedFromTeam PickedOnce BannerOnWheel WheelFrozenWhileSpinning NoDuplicateSlices NotPickedWhileHeld)
KNOWN_FINDINGS=()
props=(${@:-$ALL})
out=${HERE:h}/.verify/tla; mkdir -p $out
rc=0
for p in $props; do
    work=$out/$p; rm -r -f $work; mkdir -p $work
    cp $SPEC_DIR/TurnOrder.tla $SPEC_DIR/MC.tla $work/
    cat > $work/MC.cfg <<CFG
CONSTANTS
    Names <- MCNames
    InitialTeam <- MCInitialTeam
    None = None
SPECIFICATION Spec
INVARIANT $p
CFG
    if (cd $work && java -XX:+UseParallelGC -cp $JAR tlc2.TLC -workers auto -metadir states MC.tla > $out/$p.log 2>&1); then
        result=pass
    else
        result=FAIL
    fi
    states=$(grep -o '[0-9,]* distinct states found' $out/$p.log | head -1)
    if (( ${KNOWN_FINDINGS[(Ie)$p]} )); then
        if [[ $result == FAIL ]]; then print "known  $p (still fails, as recorded)  $states"; else print "FIXED? $p now passes: update the skill's findings"; rc=1; fi
    else
        print "${(r:6:)result} $p  $states"
        [[ $result == pass ]] || rc=1
    fi
    if [[ $result == FAIL ]]; then
        grep -q "Error: Invariant $p is violated" $out/$p.log || { print "  TLC did not finish cleanly; see $out/$p.log"; rc=2; }
        print "  trace: $out/$p.log"
    fi
done
exit $rc
