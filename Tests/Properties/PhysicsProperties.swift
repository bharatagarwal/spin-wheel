import Foundation
import PropertyBased
import Testing
@testable import HotPotatoCore

struct Watch {
    var deepestOverlap = 0.0
    var widestSwing = 0.0
    var fastestCoast = 0.0

    mutating func observe(_ sim: WheelSim, coasting: Bool) {
        deepestOverlap = max(deepestOverlap, overlap(sim))
        widestSwing = max(widestSwing, abs(sim.rootFromVertical), abs(sim.tipFromVertical))
        if coasting { fastestCoast = max(fastestCoast, abs(sim.clockwiseSpeed)) }
    }
}

func distance(from point: YDownPoint, toSegmentFrom start: YDownPoint, to end: YDownPoint) -> Double {
    let abx = end.x - start.x, aby = end.y - start.y
    let along = min(max(((point.x - start.x) * abx + (point.y - start.y) * aby) / (abx * abx + aby * aby), 0), 1)
    let offsetX = point.x - (start.x + along * abx), offsetY = point.y - (start.y + along * aby)
    return (offsetX * offsetX + offsetY * offsetY).squareRoot()
}

func overlap(_ sim: WheelSim) -> Double {
    let flapper = WheelRadii.flapper(rootFromVertical: sim.rootFromVertical, tipFromVertical: sim.tipFromVertical)
    let segment = 2 * Double.pi / Double(sim.slices)
    let pointer = -Double.pi / 2 - sim.clockwiseAngle
    let near = Int(floor((pointer - 0.5) / segment))...Int(ceil((pointer + 0.5) / segment))
    return near.map { index in
        let peg = WheelRadii.peg(index, of: sim.slices, wheelAngle: sim.clockwiseAngle)
        let gap = min(distance(from: peg, toSegmentFrom: flapper.pivot, to: flapper.joint),
                      distance(from: peg, toSegmentFrom: flapper.joint, to: flapper.tip))
        return WheelRadii.pegRadius + WheelRadii.armRadius - gap
    }.max() ?? 0
}

func coastToRest(_ sim: inout WheelSim, frames: [Double] = [1.0 / 120], watch: inout Watch) {
    var frame = 0
    while !sim.stopped && sim.time < 40 {
        sim.advance(frames[frame % frames.count], onStep: { watch.observe($0, coasting: true) })
        frame += 1
    }
}

let teamSize = Gen.int(in: 1...40)
let startAngle = Gen.double(in: 0..<(2 * .pi))
let flick = Gen.double(in: -60...60)

func push(flicked measured: Double, seed: UInt64) -> Double {
    var rng = SplitMix64(state: seed)
    return flickVelocity(measured, using: &rng)
}

let mostAPegMayBeSquashed = WheelRadii.pegRadius

@Test func anyTeamSizeComesToRestByFrictionBeforeTheCap() async {
    await propertyCheck(count: 150, input: teamSize, startAngle, flick, Gen.uint64()) { slices, start, measured, seed in
        var sim = WheelSim(slices: slices, clockwiseAngle: start)
        sim.push(push(flicked: measured, seed: seed))
        var watch = Watch()
        coastToRest(&sim, watch: &watch)
        #expect(sim.stopped && sim.time < 29.9, "stopped \(sim.stopped) after \(sim.time) s")
        #expect((0..<slices).contains(sim.winner))
    }
}

@Test func theFlapperNeverPassesThroughAPeg() async {
    await propertyCheck(count: 150, input: teamSize, startAngle, flick, Gen.uint64()) { slices, start, measured, seed in
        var sim = WheelSim(slices: slices, clockwiseAngle: start)
        sim.push(push(flicked: measured, seed: seed))
        var watch = Watch()
        coastToRest(&sim, watch: &watch)
        #expect(watch.deepestOverlap < mostAPegMayBeSquashed, "overlap \(watch.deepestOverlap)")
        #expect(watch.widestSwing < .pi / 2, "swing \(watch.widestSwing)")
    }
}

@Test func aCoastingWheelNeverSpeedsUp() async {
    await propertyCheck(count: 150, input: teamSize, startAngle, flick, Gen.uint64()) { slices, start, measured, seed in
        var sim = WheelSim(slices: slices, clockwiseAngle: start)
        let speed = push(flicked: measured, seed: seed)
        sim.push(speed)
        var watch = Watch()
        coastToRest(&sim, watch: &watch)
        #expect(watch.fastestCoast <= abs(speed) * (1 + 1e-9), "pushed at \(speed), reached \(watch.fastestCoast)")
    }
}

@Test func theFrameRateNeverChangesTheOutcome() async {
    let frameTimes = Gen.double(in: (1.0 / 240)...(1.0 / 20)).array(of: 1...12)
    await propertyCheck(count: 100, input: teamSize, startAngle, flick, frameTimes) { slices, start, measured, frames in
        let speed = push(flicked: measured, seed: 1)
        var watch = Watch()
        var steady = WheelSim(slices: slices, clockwiseAngle: start)
        steady.push(speed)
        coastToRest(&steady, watch: &watch)
        var jittery = WheelSim(slices: slices, clockwiseAngle: start)
        jittery.push(speed)
        coastToRest(&jittery, frames: frames, watch: &watch)
        #expect(jittery.clockwiseAngle == steady.clockwiseAngle && jittery.winner == steady.winner,
                "120 Hz stops at \(steady.clockwiseAngle), jittery frames at \(jittery.clockwiseAngle)")
    }
}

@Test func aMirroredSpinIsTheMirrorImage() async {
    await propertyCheck(count: 150, input: teamSize, startAngle, flick, Gen.uint64()) { slices, start, measured, seed in
        let speed = push(flicked: measured, seed: seed)
        var original = WheelSim(slices: slices, clockwiseAngle: start)
        var mirrored = WheelSim(slices: slices, clockwiseAngle: .pi - start)
        original.push(speed)
        mirrored.push(-speed)
        for _ in 0..<60 {
            original.advance(1.0 / 120)
            mirrored.advance(1.0 / 120)
        }
        #expect(abs(remainder(original.clockwiseAngle + mirrored.clockwiseAngle - .pi, 2 * .pi)) < 1e-6)
        #expect(abs(original.rootFromVertical + mirrored.rootFromVertical) < 1e-6)
        #expect(abs(original.tipFromVertical + mirrored.tipFromVertical) < 1e-6)
    }
}

struct Drag: Sendable, CustomStringConvertible {
    let fingerSpeed: Double
    let frames: Int
    var description: String { "\(frames) frames at \(fingerSpeed) rad/s" }
}

@Test func aWheelDraggedAnyWaySettlesCleanly() async {
    let drags = zip(Gen.double(in: -80...80), Gen.int(in: 1...40))
        .map { Drag(fingerSpeed: $0, frames: $1) }
        .array(of: 1...6)
    await propertyCheck(count: 150, input: teamSize, startAngle, drags, Gen.uint64()) { slices, start, drags, seed in
        var sim = WheelSim(slices: slices, clockwiseAngle: start)
        var watch = Watch()
        for drag in drags {
            for _ in 0..<drag.frames {
                sim.drive(drag.fingerSpeed)
                sim.advance(1.0 / 120, onStep: { watch.observe($0, coasting: false) })
            }
        }
        sim.push(push(flicked: drags.last?.fingerSpeed ?? 0, seed: seed))
        coastToRest(&sim, watch: &watch)
        #expect(sim.stopped && sim.time < 30 + Double(drags.map(\.frames).reduce(0, +)) / 120, "after \(sim.time) s")
        #expect(watch.deepestOverlap < mostAPegMayBeSquashed, "overlap \(watch.deepestOverlap)")
        #expect(watch.widestSwing < .pi / 2, "swing \(watch.widestSwing)")
    }
}

func sliceBetweenPegs(around point: YDownPoint, of slices: Int, wheelAngle: Double) -> Int {
    let segment = 2 * Double.pi / Double(slices)
    let inWheelFrame = atan2(point.y, point.x) - wheelAngle
    return (0..<slices).first { index in
        let fromPeg = remainder(inWheelFrame - Double(index) * segment, 2 * .pi)
        return fromPeg >= 0 && fromPeg < segment
    } ?? slices - 1
}

@Test func aFlapperRestingOnAPegGoesToTheSliceItLeansFrom() async {
    await propertyCheck(count: 300, input: teamSize, startAngle, flick, Gen.uint64()) { slices, start, measured, seed in
        var sim = WheelSim(slices: slices, clockwiseAngle: start)
        sim.push(push(flicked: measured, seed: seed))
        var watch = Watch()
        coastToRest(&sim, watch: &watch)
        let flapper = WheelRadii.flapper(rootFromVertical: sim.rootFromVertical, tipFromVertical: sim.tipFromVertical)
        let segment = 2 * Double.pi / Double(slices)
        let tipFromPeg = remainder(atan2(flapper.tip.y, flapper.tip.x) - sim.clockwiseAngle, segment)
        let restsOnAPeg = abs(tipFromPeg) < WheelRadii.pegRadius / WheelRadii.pegCircle
        let pointer = restsOnAPeg ? WheelRadii.armOverThePegTop(flapper) : flapper.tip
        let expected = sliceBetweenPegs(around: pointer, of: slices, wheelAngle: sim.clockwiseAngle)
        #expect(sim.winner == expected,
                "resting on a peg: \(restsOnAPeg); winner \(sim.winner), the arm is in \(expected)")
    }
}
