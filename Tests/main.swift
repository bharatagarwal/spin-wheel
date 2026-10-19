import Foundation

// Headless fairness check: spin the real simulation many times and
// chi-square the landing slices against a uniform distribution.

let spins = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 3000
// Critical chi-square values at p = 0.001, indexed by degrees of freedom.
let critical: [Int: Double] = [1: 10.83, 2: 13.82, 3: 16.27, 4: 18.47, 5: 20.52, 6: 22.46, 7: 24.32, 9: 27.88, 11: 31.26]
var failed = false

for slices in [2, 3, 4, 5, 6, 8, 10, 12] {
    var counts = [Int](repeating: 0, count: slices)
    var durations: [Double] = []
    var turns: [Double] = []
    var rollbacks = 0
    for _ in 0..<spins {
        let start = Double.random(in: 0..<(2 * .pi))
        var sim = WheelSim(slices: slices, theta: start)
        sim.push(spinVelocity())
        while !sim.stopped { sim.advance(1.0 / 120) }
        counts[sim.winner] += 1
        durations.append(sim.time)
        turns.append((sim.theta - start) / (2 * .pi))
        if sim.rolledBack { rollbacks += 1 }
    }
    let expected = Double(spins) / Double(slices)
    let chi = counts.reduce(0) { $0 + pow(Double($1) - expected, 2) / expected }
    let limit = critical[slices - 1] ?? .infinity
    let ok = chi < limit
    failed = failed || !ok
    durations.sort()
    turns.sort()
    func pct(_ a: [Double], _ q: Double) -> String { String(format: "%.1f", a[Int(Double(a.count - 1) * q)]) }
    print(String(format: "%2d slices  chi²=%6.2f (limit %5.2f) %@  time p10/50/90 %@/%@/%@ s  turns %@/%@/%@  rollback %4.1f%%",
                 slices, chi, limit, ok ? "ok  " : "FAIL",
                 pct(durations, 0.1), pct(durations, 0.5), pct(durations, 0.9),
                 pct(turns, 0.1), pct(turns, 0.5), pct(turns, 0.9),
                 100 * Double(rollbacks) / Double(spins)))
}
exit(failed ? 1 : 0)
