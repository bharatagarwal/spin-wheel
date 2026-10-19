---------------------------- MODULE TurnOrder ----------------------------
(* Who gets called on in Your Turn: the round phase, turn order and spin
   motion from main.swift (Model, TurnOrder, SpinSession) and the one fact
   about WheelSim that decides when a spin ends.

   Each action is one Model method or one display-link frame. SwiftUI actions
   and the CADisplayLink both run on the main thread, so each runs to
   completion before the next starts; that is what makes them atomic here.

   Left out: where the wheel stops. WheelSim may stop on any slice, so Finish
   picks any index; ./test.sh covers how often each slice wins. Shuffling is
   left out too: Reset keeps team order, and no property depends on order. *)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Names, InitialTeam, None

VARIABLES
    team,      \* Team.names
    order,     \* TurnOrder.order
    done,      \* TurnOrder.done
    wheel,     \* TurnOrder.wheel: the slices drawn on the wheel
    phase,     \* Model.phase: "idle" or "spinning"
    winner,    \* the winner in Model.Phase.idle(winner:), or None
    slices,    \* SpinSession.slices of the session in Model.Phase.spinning
    motion,    \* SpinSession.motion: "held", "coasting", or "none" with no session
    lastPick   \* not in the code: the last Finish, for the properties below

vars == <<team, order, done, wheel, phase, winner, slices, motion, lastPick>>

Range(s) == {s[i] : i \in 1..Len(s)}
Without(s, n) == SelectSeq(s, LAMBDA x : x # n)
Waiting == SelectSeq(order, LAMBDA x : x \notin done)    \* TurnOrder.waiting

Init ==
    \* ContentView.onAppear calls Model.reset().
    /\ team = InitialTeam
    /\ order = InitialTeam
    /\ done = {}
    /\ wheel = InitialTeam
    /\ phase = "idle"
    /\ winner = None
    /\ slices = <<>>
    /\ motion = "none"
    /\ lastPick = None

\* Model.begin(): guard idle and someone waiting; TurnOrder.beginSpin(); new SpinSession.
Begin(m) ==
    /\ phase = "idle"
    /\ Waiting # <<>>
    /\ wheel' = Waiting
    /\ slices' = Waiting
    /\ phase' = "spinning"
    /\ winner' = None
    /\ motion' = m
    /\ UNCHANGED <<team, order, done, lastPick>>

\* Model.spin(): begin()?.push(...). Spin button, Space, tap, accessibility action.
Spin == Begin("coasting")

\* Model.drag(to:at:) while idle: begin(), then SpinSession.grab(at:).
Grab == Begin("held")

\* Model.release() -> SpinSession.release(using:): held -> coasting, push.
Release ==
    /\ phase = "spinning" /\ motion = "held"
    /\ motion' = "coasting"
    /\ UNCHANGED <<team, order, done, wheel, phase, winner, slices, lastPick>>

\* SpinSession.frame sees sim.stopped -> onStop -> Model.finish(_:).
\* sim.winner is any slice index.
Finish(heldNow) ==
    \E i \in 1..Len(slices) :
        /\ done' = done \cup {slices[i]}
        /\ winner' = slices[i]
        /\ phase' = "idle"
        /\ motion' = "none"
        /\ slices' = <<>>
        /\ lastPick' = [name |-> slices[i], onTeam |-> slices[i] \in Range(team),
                        alreadyDone |-> slices[i] \in done, held |-> heldNow]
        /\ UNCHANGED <<team, order, wheel>>

\* WheelSim settles to .stopped only from .stuck, which a held wheel never is.
Settle == phase = "spinning" /\ motion = "coasting" /\ Finish(FALSE)

\* WheelSim.settle(): `if time > 30 { phase = .stopped }`, in any phase.
Timeout == phase = "spinning" /\ motion \in {"held", "coasting"} /\ Finish(motion = "held")

\* Model.add(): Team.add rejects duplicates; idle -> turns.add, spinning -> turns.addForNextSpin.
Add(n) ==
    /\ n \notin Range(team)
    /\ team' = Append(team, n)
    /\ order' = Append(order, n)
    /\ wheel' = IF phase = "idle" THEN Append(wheel, n) ELSE wheel
    /\ UNCHANGED <<done, phase, winner, slices, motion, lastPick>>

\* Model.remove(_:): guard idle; Team.remove; TurnOrder.remove; clear the banner if it was them.
Remove(n) ==
    /\ phase = "idle"
    /\ n \in Range(team)
    /\ team' = Without(team, n)
    /\ order' = Without(order, n)
    /\ wheel' = Without(wheel, n)
    /\ done' = done \ {n}
    /\ winner' = IF winner = n THEN None ELSE winner
    /\ UNCHANGED <<phase, slices, motion, lastPick>>

\* Model.reset(): guard idle; TurnOrder(shuffling: team.names); no banner.
Reset ==
    /\ phase = "idle"
    /\ order' = team
    /\ wheel' = team
    /\ done' = {}
    /\ winner' = None
    /\ UNCHANGED <<team, phase, slices, motion, lastPick>>

Next ==
    \/ Spin \/ Grab \/ Release \/ Settle \/ Timeout \/ Reset
    \/ \E n \in Names : Add(n) \/ Remove(n)

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Properties. Each says what the user would see go wrong if it broke. *)

\* The person called on is on the team at that moment (not someone just removed).
PickedFromTeam == lastPick = None \/ lastPick.onTeam

\* Nobody is called on twice before Reset.
PickedOnce == lastPick = None \/ ~lastPick.alreadyDone

\* The name on the banner is a slice on the wheel, so the flapper points at it.
BannerOnWheel == winner = None \/ winner \in Range(wheel)

\* While the wheel turns, the slices drawn are the slices being simulated.
WheelFrozenWhileSpinning == phase = "spinning" => wheel = slices

\* No name appears on two slices.
NoDuplicateSlices == Len(wheel) = Cardinality(Range(wheel))

\* A spin is only decided after the user lets go, so a drag can't choose the winner.
NotPickedWhileHeld == lastPick = None \/ ~lastPick.held
=============================================================================
