---------------------------- MODULE TraceCheck ----------------------------
EXTENDS Traces

VARIABLES trace, step

Shows(state) ==
    /\ team = state.team
    /\ order = state.order
    /\ done = state.done
    /\ wheel = state.wheel
    /\ phase = state.phase
    /\ winner = state.winner
    /\ slices = state.slices
    /\ motion = state.motion

ShowsNext(state) ==
    /\ team' = state.team
    /\ order' = state.order
    /\ done' = state.done
    /\ wheel' = state.wheel
    /\ phase' = state.phase
    /\ winner' = state.winner
    /\ slices' = state.slices
    /\ motion' = state.motion

TraceInit ==
    /\ trace \in 1..Len(Traces)
    /\ step = 1
    /\ Shows(Traces[trace][1])
    /\ pickRecordForProperties = None

TraceNext ==
    \/ /\ step < Len(Traces[trace])
       /\ Next
       /\ ShowsNext(Traces[trace][step + 1])
       /\ step' = step + 1
       /\ UNCHANGED trace
    \/ /\ step = Len(Traces[trace])
       /\ UNCHANGED <<vars, trace, step>>

StartsAtInit == step = 1 => Init
=============================================================================
