import Foundation
import PropertyBased
import Testing
@testable import HotPotatoCore

enum Action: Sendable, CustomStringConvertible {
    case add(String)
    case remove(String)
    case spin(stoppingAt: Double, addedMidSpin: String?)
    case newRound

    var description: String {
        switch self {
        case .add(let name): "add(\(name.debugDescription))"
        case .remove(let name): "remove(\(name.debugDescription))"
        case .spin(let angle, let late): "spin(stoppingAt: \(angle), addedMidSpin: \(late?.debugDescription ?? "nil"))"
        case .newRound: "newRound"
        }
    }
}

let memberName = Gen.element(of: ["Ana", "Ben", "Cy", "Dee", " Eve", ""]).map { $0 ?? "" }

let action = Gen<Action>.frequency(
    (3, memberName.map(Action.add).eraseToAnySequence()),
    (1, memberName.map(Action.remove).eraseToAnySequence()),
    (4, zip(Gen.double(in: 0..<(2 * .pi)), Gen.element(of: [nil, "Ana", "Fay"]).map { $0 ?? nil })
        .map { Action.spin(stoppingAt: $0, addedMidSpin: $1) }.eraseToAnySequence()),
    (1, Gen.always(Action.newRound).eraseToAnySequence())
)

struct Standup {
    var team = Team.load(from: scratchDefaults(), orFrom: [])
    var turns = TurnOrder()
    var clockwiseAngle = 0.0
    var announced: String?
    var winnersThisRound: [String] = []

    init() {
        turns = TurnOrder(shuffling: team.names)
    }

    mutating func add(_ typed: String, spinning: Bool) {
        guard let name = team.add(typed) else { return }
        if spinning { turns.addForNextSpin(name) } else { turns.add(name) }
    }

    mutating func apply(_ action: Action) {
        switch action {
        case .add(let name): add(name, spinning: false)
        case .remove(let name):
            team.remove(name)
            turns.remove(name)
            winnersThisRound.removeAll { $0 == name }
            if announced == name { announced = nil }
        case .spin(let stoppingAt, let late):
            guard !turns.waiting.isEmpty else { return }
            let slices = turns.beginSpin()
            if let late { add(late, spinning: true) }
            clockwiseAngle = stoppingAt
            let winner = sliceUnderResting(flapperOver: slices, at: stoppingAt)
            winnersThisRound.append(winner)
            turns.markDone(winner)
            announced = winner
        case .newRound:
            turns = TurnOrder(shuffling: team.names)
            winnersThisRound = []
            announced = nil
        }
    }
}

@Test func turnOrderInvariantsHoldForAnyStandup() async {
    await propertyCheck(count: 500, input: action.array(of: 0...40)) { actions in
        var standup = Standup()
        for action in actions {
            standup.apply(action)
            let turns = standup.turns
            #expect(Set(turns.order) == Set(standup.team.names), "the turn order is the team, after \(action)")
            #expect(turns.order.count == Set(turns.order).count, "nobody is in the order twice, after \(action)")
            #expect(Set(turns.wheel).isSubset(of: turns.order), "every slice is a team member, after \(action)")
            #expect(turns.done.isSubset(of: Set(turns.order)), "only members are done, after \(action)")
            #expect(standup.winnersThisRound.count == Set(standup.winnersThisRound).count, "nobody wins twice in a round, after \(action)")
        }
    }
}

@Test func everyoneGetsATurnBeforeAnyoneGoesAgain() async {
    await propertyCheck(input: memberName.array(of: 1...8), Gen.double(in: 0..<(2 * .pi)).array(of: 20...20)) { added, stops in
        var standup = Standup()
        for name in added { standup.add(name, spinning: false) }
        let team = Set(standup.team.names)
        for stop in stops where !standup.turns.waiting.isEmpty {
            standup.apply(.spin(stoppingAt: stop, addedMidSpin: nil))
        }
        #expect(Set(standup.winnersThisRound) == team)
    }
}
