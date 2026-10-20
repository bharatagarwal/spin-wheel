---------------------------- MODULE TurnOrder ----------------------------
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Names, InitialTeam, None

VARIABLES
    team,
    order,
    done,
    wheel,
    phase,
    winner,
    slices,
    motion,
    pickRecordForProperties

vars == <<team, order, done, wheel, phase, winner, slices, motion, pickRecordForProperties>>

Range(s) == {s[i] : i \in 1..Len(s)}
Without(s, n) == SelectSeq(s, LAMBDA x : x # n)
Waiting == SelectSeq(order, LAMBDA x : x \notin done)

Init ==
    /\ team = InitialTeam
    /\ order = InitialTeam
    /\ done = {}
    /\ wheel = InitialTeam
    /\ phase = "idle"
    /\ winner = None
    /\ slices = <<>>
    /\ motion = "none"
    /\ pickRecordForProperties = None

Begin(m) ==
    /\ phase = "idle"
    /\ Waiting # <<>>
    /\ wheel' = Waiting
    /\ slices' = Waiting
    /\ phase' = "spinning"
    /\ winner' = None
    /\ motion' = m
    /\ UNCHANGED <<team, order, done, pickRecordForProperties>>

Spin == Begin("coasting")

Grab == Begin("held")

Release ==
    /\ phase = "spinning" /\ motion = "held"
    /\ motion' = "coasting"
    /\ UNCHANGED <<team, order, done, wheel, phase, winner, slices, pickRecordForProperties>>

Finish ==
    \E i \in 1..Len(slices) :
        /\ done' = done \cup {slices[i]}
        /\ winner' = slices[i]
        /\ phase' = "idle"
        /\ motion' = "none"
        /\ slices' = <<>>
        /\ pickRecordForProperties' = [name |-> slices[i], onTeam |-> slices[i] \in Range(team),
                        alreadyDone |-> slices[i] \in done, held |-> motion = "held"]
        /\ UNCHANGED <<team, order, wheel>>

Stop == phase = "spinning" /\ motion = "coasting" /\ Finish

Add(n) ==
    /\ n \notin Range(team)
    /\ team' = Append(team, n)
    /\ order' = Append(order, n)
    /\ wheel' = IF phase = "idle" THEN Append(wheel, n) ELSE wheel
    /\ UNCHANGED <<done, phase, winner, slices, motion, pickRecordForProperties>>

Remove(n) ==
    /\ phase = "idle"
    /\ n \in Range(team)
    /\ team' = Without(team, n)
    /\ order' = Without(order, n)
    /\ wheel' = Without(wheel, n)
    /\ done' = done \ {n}
    /\ winner' = IF winner = n THEN None ELSE winner
    /\ UNCHANGED <<phase, slices, motion, pickRecordForProperties>>

Reset ==
    /\ phase = "idle"
    /\ order' = team
    /\ wheel' = team
    /\ done' = {}
    /\ winner' = None
    /\ UNCHANGED <<team, phase, slices, motion, pickRecordForProperties>>

Next ==
    \/ Spin \/ Grab \/ Release \/ Stop \/ Reset
    \/ \E n \in Names : Add(n) \/ Remove(n)

Spec == Init /\ [][Next]_vars

UserLetsGo == WF_vars(Release)

WheelComesToRest == WF_vars(Stop)

FairSpec == Spec /\ UserLetsGo /\ WheelComesToRest

-----------------------------------------------------------------------------
PickedFromTeam == pickRecordForProperties = None \/ pickRecordForProperties.onTeam

PickedOnce == pickRecordForProperties = None \/ ~pickRecordForProperties.alreadyDone

BannerOnWheel == winner = None \/ winner \in Range(wheel)

WheelFrozenWhileSpinning == phase = "spinning" => wheel = slices

NoDuplicateSlices == Len(wheel) = Cardinality(Range(wheel))

NotPickedWhileHeld == pickRecordForProperties = None \/ ~pickRecordForProperties.held

SpinsEnd == phase = "spinning" ~> phase = "idle"
=============================================================================
