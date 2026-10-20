import Foundation

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

let arguments = CommandLine.arguments.dropFirst().compactMap { UInt64($0) }
let spins = Int(arguments.first ?? 3000)
let seed = arguments.dropFirst().first ?? UInt64.random(in: 0...UInt64(UInt32.max))
var rng = SplitMix64(state: seed)
print("seed \(seed)  (replay: ./test.sh \(spins) \(seed))")

let fixedStartsPerSize = 4
let zAtP001 = 3.0902
let shortestP10Spin = 3.0, longestP90Spin = 5.5

func chiSquareAtP001(degreesOfFreedom: Int) -> Double {
    let freedom = Double(degreesOfFreedom), spread = 2 / (9 * freedom)
    return freedom * pow(1 - spread + zAtP001 * spread.squareRoot(), 3)
}

var failed = false

for slices in [2, 3, 4, 5, 6, 8, 10, 12] {
    let starts = (0..<fixedStartsPerSize).map { _ in Double.random(in: 0..<(2 * .pi), using: &rng) }
    var countsByStart = [[Int]](repeating: [Int](repeating: 0, count: slices), count: fixedStartsPerSize)
    var durations: [Double] = [], turns: [Double] = [], swings: [Double] = [], bends: [Double] = [], tips: [Double] = []
    var rollbacks = 0
    for spin in 0..<spins {
        let startIndex = spin % fixedStartsPerSize
        let start = starts[startIndex]
        var sim = WheelSim(slices: slices, clockwiseAngle: start)
        let speed = spinVelocity(using: &rng)
        sim.push(spin / fixedStartsPerSize % 2 == 0 ? speed : -flickVelocity(speed, using: &rng))
        var peakRoot = 0.0, peakBend = 0.0, peakTip = 0.0, rolledBack = false
        while !sim.stopped {
            sim.advance(1.0 / 120, onStep: { step in
                peakRoot = max(peakRoot, abs(step.rootFromVertical))
                peakBend = max(peakBend, abs(step.tipFromVertical - step.rootFromVertical))
                peakTip = max(peakTip, abs(step.tipFromVertical))
                if step.clockwiseSpeed * step.pushDirection < -0.05 { rolledBack = true }
            })
        }
        countsByStart[startIndex][sim.winner] += 1
        durations.append(sim.time)
        turns.append(abs(sim.clockwiseAngle - start) / (2 * .pi))
        swings.append(peakRoot * 180 / .pi)
        bends.append(peakBend * 180 / .pi)
        tips.append(peakTip * 180 / .pi)
        if rolledBack { rollbacks += 1 }
    }
    let expected = Double(spins / fixedStartsPerSize) / Double(slices)
    let chi = countsByStart.joined().reduce(0) { $0 + pow(Double($1) - expected, 2) / expected }
    let limit = chiSquareAtP001(degreesOfFreedom: fixedStartsPerSize * (slices - 1))
    let fair = chi < limit
    let sortedDurations = durations.sorted()
    let lengthOK = sortedDurations[spins / 10] >= shortestP10Spin && sortedDurations[spins * 9 / 10] <= longestP90Spin
    let passed = fair && lengthOK
    failed = failed || !passed
    func p50(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    func spread(_ values: [Double]) -> String {
        let sorted = values.sorted()
        return String(format: "%.1f/%.1f/%.1f",
                      sorted[sorted.count / 10], sorted[sorted.count / 2], sorted[sorted.count * 9 / 10])
    }
    let verdict = fair ? (lengthOK ? "ok  " : "LONG") : "FAIL"
    print(String(format: "%2d slices  chi²=%6.2f (limit %5.2f, %d fixed starts) %@  time %@ s  turns %@  "
                     + "rollback %4.1f%%  flapper tip %2.0f° (root %2.0f° + bend %2.0f°)",
                 slices, chi, limit, fixedStartsPerSize, verdict, spread(durations), spread(turns),
                 100 * Double(rollbacks) / Double(spins), p50(tips), p50(swings), p50(bends)))
}
exit(failed ? 1 : 0)
