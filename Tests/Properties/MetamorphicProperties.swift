import Foundation
import PropertyBased
import Testing
@testable import HotPotatoCore

@Test func turningTheStartOneSliceOnCallsOnTheNextSlice() async {
    await propertyCheck(count: 150, input: Gen.int(in: 2...40), startAngle, flick, Gen.uint64()) { slices, start, measured, seed in
        let speed = push(flicked: measured, seed: seed)
        let slice = 2 * Double.pi / Double(slices)
        var watch = Watch()
        var original = WheelSim(slices: slices, clockwiseAngle: start)
        var turned = WheelSim(slices: slices, clockwiseAngle: start + slice)
        original.push(speed)
        turned.push(speed)
        coastToRest(&original, watch: &watch)
        coastToRest(&turned, watch: &watch)
        #expect(turned.winner == (original.winner + slices - 1) % slices, "\(original.winner) then \(turned.winner)")
        #expect(abs(turned.clockwiseAngle - original.clockwiseAngle - slice) < 1e-6,
                "stopped \(turned.clockwiseAngle - original.clockwiseAngle) apart, not one slice (\(slice))")
    }
}

@Test func addingSomeoneAndRemovingThemChangesNothing() async {
    await propertyCheck(count: 500, input: action.array(of: 0...20), memberName, Gen.uint64()) { actions, typed, seed in
        var recorded = RecordedStandup()
        for action in actions { recorded.apply(action) }
        var standup = recorded.standup
        var rng = SplitMix64(state: seed)
        standup.pose.rootFromVertical = Double.random(in: -0.9...0.9, using: &rng)
        standup.pose.tipFromVertical = standup.pose.rootFromVertical + Double.random(in: -0.5...0.5, using: &rng)
        let before = standup
        guard let name = standup.add(typed) else { return }
        standup.remove(name)
        #expect(tla(standup) == tla(before))
        #expect(abs(standup.pose.clockwiseAngle - before.pose.clockwiseAngle) < 1e-9,
                "\(before.pose.clockwiseAngle) → \(standup.pose.clockwiseAngle), adding and removing \(name)")
    }
}
