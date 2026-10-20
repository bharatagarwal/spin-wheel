#!/bin/zsh
set -e
HERE=${0:A:h}
SPEC_DIR=${TURNORDER_SPEC_DIR:-$HERE}
TLC_VERSION=v1.7.4
TLC_SHA256=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
JAR=${HERE:h}/.verify/tools/tla2tools-$TLC_VERSION.jar
if [[ ! -f $JAR ]]; then
    mkdir -p ${JAR:h}
    curl -sSL -o $JAR https://github.com/tlaplus/tlaplus/releases/download/$TLC_VERSION/tla2tools.jar
fi
[[ $(shasum -a 256 $JAR | cut -d' ' -f1) == $TLC_SHA256 ]] || { print "tla2tools.jar checksum mismatch"; exit 2 }

INVARIANTS=(PickedFromTeam PickedOnce BannerOnWheel WheelFrozenWhileSpinning NoDuplicateSlices NotPickedWhileHeld)
LIVENESS=(SpinsEnd)
ALL=($INVARIANTS $LIVENESS)
KNOWN_FINDINGS=()
out=${HERE:h}/.verify/tla; mkdir -p $out

if [[ $1 == traces ]]; then
    work=$out/traces; rm -r -f $work $out/traces.log; mkdir -p $work
    (cd ${HERE:h} && ./property-test.sh --filter theRealStandupLeavesTracesForTLC > $out/traces-swift.log 2>&1) ||
        { print "FAIL   traces: the Swift run failed; see $out/traces-swift.log"; exit 1 }
    cp $SPEC_DIR/TurnOrder.tla $HERE/TraceCheck.tla ${HERE:h}/.verify/traces/Traces.tla $work/
    cat > $work/TraceCheck.cfg <<CFG
CONSTANTS
    Names <- TraceNames
    InitialTeam <- TraceTeam
    None = None
INIT TraceInit
NEXT TraceNext
INVARIANT StartsAtInit $INVARIANTS
CFG
    if (cd $work && java -XX:+UseParallelGC -cp $JAR tlc2.TLC -workers auto -metadir states TraceCheck.tla > $out/traces.log 2>&1); then
        print "pass   traces  $(grep -o '[0-9,]* distinct states found' $out/traces.log | head -1)"
        exit 0
    fi
    rejected=$(grep -o '^/\\ \(trace\|step\) = [0-9]*' $out/traces.log | tail -2 | tr -d '/\\' | paste -sd, -)
    print "FAIL   traces: the code took a step the model does not allow, after${rejected:- the first state}; see $out/traces.log"
    exit 1
fi

props=(${@:-$ALL})
rc=0
for p in $props; do
    work=$out/$p; rm -r -f $work; mkdir -p $work
    cp $SPEC_DIR/TurnOrder.tla $SPEC_DIR/MC.tla $work/
    if (( ${LIVENESS[(Ie)$p]} )); then
        check="SPECIFICATION FairSpec
PROPERTY $p"
        violation="Temporal properties were violated"
    else
        check="SPECIFICATION Spec
INVARIANT $p"
        violation="Invariant $p is violated"
    fi
    cat > $work/MC.cfg <<CFG
CONSTANTS
    Names <- MCNames
    InitialTeam <- MCInitialTeam
    None = None
$check
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
        grep -q "Error: $violation" $out/$p.log || { print "  TLC did not finish cleanly; see $out/$p.log"; rc=2; }
        print "  trace: $out/$p.log"
    fi
done
exit $rc
