import Foundation

let spins = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 3000
let chiSquareAtP001ByDegreesOfFreedom: [Int: Double] = [1: 10.83, 2: 13.82, 3: 16.27, 4: 18.47, 5: 20.52, 6: 22.46, 7: 24.32, 9: 27.88, 11: 31.26]
var failed = false

for slices in [2, 3, 4, 5, 6, 8, 10, 12] {
    var counts = [Int](repeating: 0, count: slices)
    var durations: [Double] = [], turns: [Double] = [], swings: [Double] = [], bends: [Double] = [], tips: [Double] = []
    var rollbacks = 0
    for n in 0..<spins {
        let start = Double.random(in: 0..<(2 * .pi))
        var sim = WheelSim(slices: slices, theta: start)
        sim.push(n % 2 == 0 ? spinVelocity() : -flickVelocity(spinVelocity()))
        while !sim.stopped { sim.advance(1.0 / 120) }
        counts[sim.winner] += 1
        durations.append(sim.time)
        turns.append(abs(sim.theta - start) / (2 * .pi))
        swings.append(sim.peakRoot * 180 / .pi)
        bends.append(sim.peakBend * 180 / .pi)
        tips.append(sim.peakTip * 180 / .pi)
        if sim.rolledBack { rollbacks += 1 }
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
