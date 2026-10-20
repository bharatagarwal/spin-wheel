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
    var pose = WheelPose()
    var announced: String?
    var winnersThisRound: [String] = []

    init() {
        turns = TurnOrder(shuffling: team.names)
    }

    mutating func add(_ typed: String, spinning: Bool) {
        guard let name = team.add(typed) else { return }
        if spinning { turns.addForNextSpin(name) } else { keepingTheWinnerUnderTheFlapper { $0.add(name) } }
    }

    mutating func keepingTheWinnerUnderTheFlapper(_ change: (inout TurnOrder) -> Void) {
        let before = turns.wheel
        change(&turns)
        guard let announced, let old = before.firstIndex(of: announced), let new = turns.wheel.firstIndex(of: announced) else { return }
        pose.clockwiseAngle = pose.clockwiseAngle(keepingSlice: old, of: before.count, underTheFlapperAs: new, of: turns.wheel.count)
    }

    mutating func apply(_ action: Action) {
        switch action {
        case .add(let name): add(name, spinning: false)
        case .remove(let name):
            team.remove(name)
            keepingTheWinnerUnderTheFlapper { $0.remove(name) }
            winnersThisRound.removeAll { $0 == name }
            if announced == name { announced = nil }
        case .spin(let stoppingAt, let late):
            guard !turns.waiting.isEmpty else { return }
            let slices = turns.beginSpin()
            if let late { add(late, spinning: true) }
            pose.clockwiseAngle = stoppingAt
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

@Test func theFlapperKeepsPointingAtTheAnnouncedWinner() async {
    await propertyCheck(count: 500, input: action.array(of: 0...20)) { actions in
        var standup = Standup()
        for action in actions {
            standup.apply(action)
            guard let announced = standup.announced else { continue }
            let pointedAt = sliceUnderResting(flapperOver: standup.turns.wheel, at: standup.pose.clockwiseAngle)
            #expect(pointedAt == announced, "banner says \(announced), flapper points at \(pointedAt), after \(action)")
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

@Test func reslicingKeepsTheFlapperAtTheSameSpotInTheWinnersSlice() async {
    let bend = Gen.double(in: -0.6...0.6)
    await propertyCheck(count: 2000, input: zip(Gen.int(in: 1...40), Gen.int(in: 1...40)), Gen.double(in: -100...100), bend, bend) { sizes, angle, root, tip in
        let (oldSlices, newSlices) = sizes
        let pose = WheelPose(clockwiseAngle: angle, rootFromVertical: root, tipFromVertical: tip)
        let flapperTip = WheelRadii.flapper(rootFromVertical: root, tipFromVertical: tip).tip
        let before = WheelRadii.slicesFromFirst(to: flapperTip, wheelAngle: angle, slices: oldSlices)
        let old = Int(before), new = old % newSlices
        let turned = pose.clockwiseAngle(keepingSlice: old, of: oldSlices, underTheFlapperAs: new, of: newSlices)
        let after = WheelRadii.slicesFromFirst(to: flapperTip, wheelAngle: turned, slices: newSlices)
        #expect(Int(after) == new && abs((after - Double(new)) - (before - Double(old))) < 1e-9, "\(before) → \(after)")
        #expect(abs(turned - angle) <= .pi + 1e-9, "turns the short way")
    }
}
