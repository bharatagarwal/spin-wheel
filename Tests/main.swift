import Foundation

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

let arguments = CommandLine.arguments.dropFirst().compactMap { UInt64($0) }
let spins = Int(arguments.first ?? 3000)
let seed = arguments.dropFirst().first ?? UInt64.random(in: 0...UInt64(UInt32.max))
var rng = SplitMix64(state: seed)
print("seed \(seed)  (replay: ./test.sh \(spins) \(seed))")

let chiSquareAtP001ByDegreesOfFreedom: [Int: Double] = [1: 10.83, 2: 13.82, 3: 16.27, 4: 18.47, 5: 20.52, 6: 22.46, 7: 24.32, 9: 27.88, 11: 31.26]
var failed = false

for slices in [2, 3, 4, 5, 6, 8, 10, 12] {
    var counts = [Int](repeating: 0, count: slices)
    var durations: [Double] = [], turns: [Double] = [], swings: [Double] = [], bends: [Double] = [], tips: [Double] = []
    var rollbacks = 0
    for n in 0..<spins {
        let start = Double.random(in: 0..<(2 * .pi), using: &rng)
        var sim = WheelSim(slices: slices, clockwiseAngle: start)
        let speed = spinVelocity(using: &rng)
        sim.push(n % 2 == 0 ? speed : -flickVelocity(speed, using: &rng))
        var peakRoot = 0.0, peakBend = 0.0, peakTip = 0.0, rolledBack = false
        while !sim.stopped {
            sim.advance(1.0 / 120, onStep: { s in
                peakRoot = max(peakRoot, abs(s.rootFromVertical))
                peakBend = max(peakBend, abs(s.tipFromVertical - s.rootFromVertical))
                peakTip = max(peakTip, abs(s.tipFromVertical))
                if s.clockwiseSpeed * s.pushDirection < -0.05 { rolledBack = true }
            })
        }
        counts[sim.winner] += 1
        durations.append(sim.time)
        turns.append(abs(sim.clockwiseAngle - start) / (2 * .pi))
        swings.append(peakRoot * 180 / .pi)
        bends.append(peakBend * 180 / .pi)
        tips.append(peakTip * 180 / .pi)
        if rolledBack { rollbacks += 1 }
    }
    let expected = Double(spins) / Double(slices)
    let chi = counts.reduce(0) { $0 + pow(Double($1) - expected, 2) / expected }
    let limit = chiSquareAtP001ByDegreesOfFreedom[slices - 1] ?? .infinity
    let ok = chi < limit
    failed = failed || !ok
    func p50(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
    func spread(_ a: [Double]) -> String {
        let s = a.sorted()
        return String(format: "%.1f/%.1f/%.1f", s[s.count / 10], s[s.count / 2], s[s.count * 9 / 10])
    }
    print(String(format: "%2d slices  chi²=%6.2f (limit %5.2f) %@  time %@ s  turns %@  rollback %4.1f%%  flapper tip %2.0f° (root %2.0f° + bend %2.0f°)",
                 slices, chi, limit, ok ? "ok  " : "FAIL", spread(durations), spread(turns),
                 100 * Double(rollbacks) / Double(spins), p50(tips), p50(swings), p50(bends)))
}
exit(failed ? 1 : 0)
