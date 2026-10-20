import Foundation
import Testing
@testable import HotPotatoCore

enum Act: CaseIterable {
    case begin, finish, add, remove, reset
}

enum Phase: CaseIterable {
    case idle, spinning
}

enum Waiting: CaseIterable {
    case nobody, somebody
}

enum Named: CaseIterable {
    case newcomer, member
}

enum Outcome {
    case nothing, startsASpin, callsOnASlice, joinsTheWheel, joinsTheNextSpin, leaves, startsANewRound, cannotHappen
}

struct Case: CustomStringConvertible {
    let act: Act
    let phase: Phase
    let waiting: Waiting
    let named: Named

    var description: String { "\(act) \(phase) \(waiting) \(named)" }
}

struct Decision {
    var act: Act?
    var phase: Phase?
    var waiting: Waiting?
    var named: Named?
    var outcome: Outcome

    func covers(_ situation: Case) -> Bool {
        (act ?? situation.act) == situation.act && (phase ?? situation.phase) == situation.phase
            && (waiting ?? situation.waiting) == situation.waiting && (named ?? situation.named) == situation.named
    }
}

let decisions = [
    Decision(phase: .spinning, waiting: .nobody, outcome: .cannotHappen),
    Decision(act: .begin, phase: .idle, waiting: .somebody, outcome: .startsASpin),
    Decision(act: .begin, phase: .idle, waiting: .nobody, outcome: .nothing),
    Decision(act: .begin, phase: .spinning, waiting: .somebody, outcome: .nothing),
    Decision(act: .finish, phase: .idle, outcome: .nothing),
    Decision(act: .finish, phase: .spinning, waiting: .somebody, outcome: .callsOnASlice),
    Decision(act: .add, phase: .idle, named: .newcomer, outcome: .joinsTheWheel),
    Decision(act: .add, phase: .spinning, waiting: .somebody, named: .newcomer, outcome: .joinsTheNextSpin),
    Decision(act: .add, phase: .idle, named: .member, outcome: .nothing),
    Decision(act: .add, phase: .spinning, waiting: .somebody, named: .member, outcome: .nothing),
    Decision(act: .remove, phase: .idle, named: .member, outcome: .leaves),
    Decision(act: .remove, phase: .idle, named: .newcomer, outcome: .nothing),
    Decision(act: .remove, phase: .spinning, waiting: .somebody, outcome: .nothing),
    Decision(act: .reset, phase: .idle, outcome: .startsANewRound),
    Decision(act: .reset, phase: .spinning, waiting: .somebody, outcome: .nothing)
]

let everyCase = Act.allCases.flatMap { act in
    Phase.allCases.flatMap { phase in
        Waiting.allCases.flatMap { waiting in
            Named.allCases.map { Case(act: act, phase: phase, waiting: waiting, named: $0) }
        }
    }
}

@Test func everyCaseHasExactlyOneDecision() {
    for situation in everyCase {
        let matching = decisions.filter { $0.covers(situation) }
        #expect(matching.count == 1, "\(situation): \(matching.map(\.outcome))")
    }
}

let newcomer = Name("Zed")!

func check(_ outcome: Outcome, of act: Act, by name: Name,
           from before: Standup<StopsWhereTold>, to after: Standup<StopsWhereTold>) {
    let was = before.turns, now = after.turns
    switch outcome {
    case .nothing:
        #expect(tla(after) == tla(before))
    case .startsASpin:
        #expect(after.spin?.slices == was.waiting && now.wheel == was.waiting)
        #expect(now.order == was.order && now.done == was.done)
    case .callsOnASlice:
        #expect(after.winner.map(before.spin!.slices.contains) == true)
        #expect(now.done == was.done.union([after.winner!]) && now.wheel == was.wheel)
    case .joinsTheWheel:
        #expect(after.team.names == before.team.names + [name])
        #expect(now.order == was.order + [name] && now.wheel == was.wheel + [name])
        #expect(after.winner == before.winner)
    case .joinsTheNextSpin:
        #expect(after.team.names == before.team.names + [name])
        #expect(now.order == was.order + [name] && now.wheel == was.wheel)
        #expect(after.spin === before.spin)
    case .leaves:
        #expect(after.team.names == before.team.names.filter { $0 != name })
        #expect(now.order == was.order.filter { $0 != name })
        #expect(now.wheel == was.wheel.filter { $0 != name } && now.done == was.done.subtracting([name]))
        #expect(after.winner == (before.winner == name ? nil : before.winner) && after.spin == nil)
    case .startsANewRound:
        #expect(now.done.isEmpty && after.winner == nil)
        #expect(Set(now.order) == Set(after.team.names) && now.wheel == now.order)
    case .cannotHappen:
        Issue.record("reached a case the table says cannot happen: \(tla(before))")
    }
}

func apply(_ act: Act, by name: Name, to standup: inout Standup<StopsWhereTold>,
           using rng: inout some RandomNumberGenerator) {
    switch act {
    case .begin: _ = standup.begin { slices, _ in StopsWhereTold(slices: slices) }
    case .finish: _ = standup.spin.map { standup.finish(atSlice: Int.random(in: $0.slices.indices, using: &rng)) }
    case .add: _ = standup.add(name.text)
    case .remove: standup.remove(name)
    case .reset: standup.reset()
    }
}

@Test func everyDecisionIsWhatStandupDoes() {
    var rng = SplitMix64(state: 7)
    var taken = Set<Int>()
    for _ in 0..<200 {
        var standup = Standup<StopsWhereTold>(team: defaultTeam())
        for _ in 0..<30 {
            let phase: Phase = standup.spin == nil ? .idle : .spinning
            let waiting: Waiting = standup.turns.waiting.isEmpty ? .nobody : .somebody
            for act in Act.allCases {
                let someone = standup.team.names.randomElement(using: &rng)
                for (named, name) in [(Named.newcomer, newcomer), (.member, someone)] {
                    let situation = Case(act: act, phase: phase, waiting: waiting, named: named)
                    guard let name, let row = decisions.firstIndex(where: { $0.covers(situation) }) else { continue }
                    taken.insert(row)
                    var after = standup
                    apply(act, by: name, to: &after, using: &rng)
                    check(decisions[row].outcome, of: act, by: name, from: standup, to: after)
                }
            }
            standup.take(Step.allCases.randomElement(using: &rng)!, using: &rng)
        }
    }
    let untaken = decisions.indices.filter { !taken.contains($0) && decisions[$0].outcome != .cannotHappen }
    #expect(untaken.isEmpty, "rows never exercised: \(untaken.map { decisions[$0] })")
}
