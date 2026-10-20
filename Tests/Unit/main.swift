import Foundation

var failures = 0
func expect(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAIL  line \(line): \(what)") }
}

func names(_ typed: String...) -> [Name] { typed.compactMap(Name.init) }

func scratchDefaults(_ names: String?) -> UserDefaults {
    let suite = "hotpotato.unit-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    if let names { defaults.set(names, forKey: "names") }
    return defaults
}

do {
    let defaults = scratchDefaults("Ana\n Ben \nAna\n\nCy\nBen")
    let team = Team.load(from: defaults, orFrom: [])
    expect(team.names.map(\.text) == ["Ana", "Ben", "Cy"], "load drops duplicate and blank saved names, got \(team.names)")
    expect(defaults.string(forKey: "names") == "Ana\nBen\nCy", "load writes the cleaned list back")
}

do {
    let previous = scratchDefaults("Old\nNames")
    let team = Team.load(from: scratchDefaults(nil), orFrom: [scratchDefaults(nil), previous])
    expect(team.names.map(\.text) == ["Old", "Names"], "load migrates from the first previous app that has names, got \(team.names)")
}

do {
    var team = Team.load(from: scratchDefaults("Ana"), orFrom: [])
    expect(team.add("Ana") == nil, "add rejects a duplicate")
    expect(team.add(" \u{200B}\n") == nil, "add rejects a name with nothing visible in it")
    expect(team.add(" Ben\r\n Cy ")?.text == "Ben Cy" && team.names.map(\.text) == ["Ana", "Ben Cy"], "add keeps a typed name on one line")
    expect(team.add("👩\u{200D}💻")?.text == "👩\u{200D}💻", "add keeps the joiners inside an emoji")
    team.remove(Name("Ana")!)
    expect(team.names.map(\.text) == ["Ben Cy", "👩\u{200D}💻"], "remove drops the name")
}

do {
    var turns = TurnOrder(shuffling: names("Ana", "Ben", "Cy"))
    let slices = turns.beginSpin()
    turns.addForNextSpin(Name("Dee")!)
    expect(turns.wheel == slices, "a name added mid-spin doesn't change the wheel being spun")
    turns.markDone(slices[0])
    expect(turns.wheel == slices, "the winner's slice stays on the wheel until the next spin")
    let next = turns.beginSpin()
    expect(!next.contains(slices[0]) && next.contains(Name("Dee")!) && next.count == 3, "next spin drops the winner and includes the late add, got \(next)")
}

do {
    var turns = TurnOrder(shuffling: names("Ana", "Ben", "Cy"))
    let slices = turns.beginSpin()
    turns.markDone(slices[0])
    turns.remove(slices[0])
    expect(!turns.wheel.contains(slices[0]) && !turns.done.contains(slices[0]) && !turns.order.contains(slices[0]), "removing the winner removes them everywhere")
}

do {
    var turns = TurnOrder(shuffling: names("Ana", "Ben", "Cy"))
    for _ in 0..<3 { turns.markDone(turns.beginSpin()[0]) }
    expect(turns.waiting.isEmpty, "everyone has had a turn after three picks")
    turns = TurnOrder(shuffling: names("Ana", "Ben", "Cy"))
    expect(Set(turns.waiting) == Set(names("Ana", "Ben", "Cy")) && turns.done.isEmpty, "a new round puts everyone back")
}

do {
    var sim = WheelSim(slices: 5)
    for _ in 0..<(120 * 40) { sim.drive(0); sim.advance(1.0 / 120) }
    expect(!sim.stopped, "a wheel held for 40 s has not stopped")
    var rng = SystemRandomNumberGenerator()
    sim.push(spinVelocity(using: &rng))
    var frames = 0
    while !sim.stopped && frames < 120 * 31 { sim.advance(1.0 / 120); frames += 1 }
    let seconds = Double(frames) / 120
    expect(sim.stopped && seconds > 1, "after release it spins and stops, took \(seconds) s")
}

do {
    var rng = SystemRandomNumberGenerator()
    let pushes = (0..<2000).map { _ in flickVelocity(-30, using: &rng) }
    expect(pushes.allSatisfy { $0 < 0 }, "an anticlockwise flick spins anticlockwise")
    expect(pushes.allSatisfy { abs($0) <= flickPushMeanSpeeds.upperBound + pushSpeedMaxDeviations * pushSpeedStandardDeviation }, "a hard flick is capped")
}

print(failures == 0 ? "unit tests: all passed" : "unit tests: \(failures) failed")
exit(failures == 0 ? 0 : 1)
