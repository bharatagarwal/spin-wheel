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

final class StopsWhereTold: Spinning {
    let slices: [Name]
    var held = false

    init(slices: [Name]) {
        self.slices = slices
    }
}

struct RecordedStandup {
    var standup = Standup<StopsWhereTold>(team: defaultTeam())
    var winnersThisRound: [Name] = []

    mutating func apply(_ action: Action) {
        switch action {
        case .add(let name): _ = standup.add(name)
        case .remove(let typed):
            guard let name = Name(typed) else { return }
            standup.remove(name)
            winnersThisRound.removeAll { $0 == name }
        case .spin(let stoppingAt, let late):
            guard let spin = standup.begin({ slices, _ in StopsWhereTold(slices: slices) }) else { return }
            if let late { _ = standup.add(late) }
            standup.pose.clockwiseAngle = stoppingAt
            let winner = WheelSim(slices: spin.slices.count, clockwiseAngle: stoppingAt).winner
            winnersThisRound.append(standup.finish(atSlice: winner)!)
        case .newRound:
            standup.reset()
            winnersThisRound = []
        }
    }
}

@Test func turnOrderInvariantsHoldForAnyStandup() async {
    await propertyCheck(count: 500, input: action.array(of: 0...40)) { actions in
        var recorded = RecordedStandup()
        for action in actions {
            recorded.apply(action)
            let turns = recorded.standup.turns
            #expect(Set(turns.order) == Set(recorded.standup.team.names), "the turn order is the team, after \(action)")
            #expect(turns.order.count == Set(turns.order).count, "nobody is in the order twice, after \(action)")
            #expect(Set(turns.wheel).isSubset(of: turns.order), "every slice is a team member, after \(action)")
            #expect(turns.done.isSubset(of: Set(turns.order)), "only members are done, after \(action)")
            #expect(recorded.winnersThisRound.count == Set(recorded.winnersThisRound).count,
                    "nobody wins twice in a round, after \(action)")
        }
    }
}

@Test func theFlapperKeepsPointingAtTheAnnouncedWinner() async {
    await propertyCheck(count: 500, input: action.array(of: 0...20)) { actions in
        var recorded = RecordedStandup()
        for action in actions {
            recorded.apply(action)
            guard let announced = recorded.standup.winner else { continue }
            let pointedAt = sliceUnderResting(flapperOver: recorded.standup.turns.wheel,
                                              at: recorded.standup.pose.clockwiseAngle)
            #expect(pointedAt == announced, "banner says \(announced), flapper points at \(pointedAt), after \(action)")
        }
    }
}

@Test func everyoneGetsATurnBeforeAnyoneGoesAgain() async {
    let stops = Gen.double(in: 0..<(2 * .pi)).array(of: 20...20)
    await propertyCheck(input: memberName.array(of: 1...8), stops) { added, stops in
        var recorded = RecordedStandup()
        for name in added { _ = recorded.standup.add(name) }
        let team = Set(recorded.standup.team.names)
        for stop in stops where !recorded.standup.turns.waiting.isEmpty {
            recorded.apply(.spin(stoppingAt: stop, addedMidSpin: nil))
        }
        #expect(Set(recorded.winnersThisRound) == team)
    }
}

@Test func reslicingKeepsTheFlapperAtTheSameSpotInTheWinnersSlice() async {
    let bend = Gen.double(in: -0.6...0.6)
    let sizes = zip(Gen.int(in: 1...40), Gen.int(in: 1...40))
    await propertyCheck(count: 2000, input: sizes, Gen.double(in: -100...100), bend, bend) { sizes, angle, root, tip in
        let (oldSlices, newSlices) = sizes
        let pose = WheelPose(clockwiseAngle: angle, rootFromVertical: root, tipFromVertical: tip)
        let flapperTip = WheelRadii.flapper(rootFromVertical: root, tipFromVertical: tip).tip
        let before = WheelRadii.slicesFromFirst(to: flapperTip, wheelAngle: angle, slices: oldSlices)
        let old = Int(before), new = old % newSlices
        let turned = pose.clockwiseAngle(keepingSlice: old, of: oldSlices, underTheFlapperAs: new, of: newSlices)
        let after = WheelRadii.slicesFromFirst(to: flapperTip, wheelAngle: turned, slices: newSlices)
        #expect(Int(after) == new && abs((after - Double(new)) - (before - Double(old))) < 1e-9,
                "\(before) → \(after)")
        #expect(abs(turned - angle) <= .pi + 1e-9, "turns the short way")
    }
}
