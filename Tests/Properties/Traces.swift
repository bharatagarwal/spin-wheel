import Foundation
import Testing
@testable import HotPotatoCore

enum Step: CaseIterable {
    case add, remove, spin, grab, release, stop, reset
}

let typedNames = ["Alice", "Bob ", " Eve", "Fay\t", "", "Dana"]

func tla(_ names: [Name]) -> String {
    "<<" + names.map { "\"\($0.text)\"" }.joined(separator: ", ") + ">>"
}

func tla(_ standup: Standup<StopsWhereTold>) -> String {
    let (phase, winner, slices, motion) = switch standup.phase {
    case .idle(let winner): ("idle", winner.map { "\"\($0.text)\"" } ?? "None", "<<>>", "none")
    case .spinning(let spin): ("spinning", "None", tla(spin.slices), spin.held ? "held" : "coasting")
    }
    let done = standup.turns.done.map { "\"\($0.text)\"" }.sorted().joined(separator: ", ")
    return "[team |-> \(tla(standup.team.names)), order |-> \(tla(standup.turns.order)), done |-> {\(done)}, "
        + "wheel |-> \(tla(standup.turns.wheel)), phase |-> \"\(phase)\", winner |-> \(winner), slices |-> \(slices), motion |-> \"\(motion)\"]"
}

@Test func theRealStandupLeavesTracesForTLC() throws {
    var rng = SplitMix64(state: 2026)
    let team = Team.load(from: scratchDefaults(), orFrom: [])
    var traces: [[String]] = []
    for _ in 0..<300 {
        var standup = Standup<StopsWhereTold>(team: team)
        var trace = [tla(standup)]
        for _ in 0..<40 {
            switch Step.allCases.randomElement(using: &rng)! {
            case .add: _ = standup.add(typedNames.randomElement(using: &rng)!)
            case .remove: Name(typedNames.randomElement(using: &rng)!).map { standup.remove($0) }
            case .spin: _ = standup.begin { slices, _ in StopsWhereTold(slices: slices) }
            case .grab: standup.begin { slices, _ in StopsWhereTold(slices: slices) }?.held = true
            case .release: standup.spin?.held = false
            case .stop:
                if let spin = standup.spin, !spin.held { _ = standup.finish(atSlice: Int.random(in: spin.slices.indices, using: &rng)) }
            case .reset: standup.reset()
            }
            let state = tla(standup)
            if state != trace.last { trace.append(state) }
        }
        traces.append(trace)
    }
    let names = Set(team.names + typedNames.compactMap(Name.init)).map { "\"\($0.text)\"" }.sorted().joined(separator: ", ")
    let module = """
        ---- MODULE Traces ----
        EXTENDS TurnOrder
        TraceNames == {\(names)}
        TraceTeam == \(tla(team.names))
        Traces == <<
        \(traces.map { "<<\n" + $0.joined(separator: ",\n") + "\n>>" }.joined(separator: ",\n"))
        >>
        ====

        """
    try FileManager.default.createDirectory(atPath: ".verify/traces", withIntermediateDirectories: true)
    try module.write(toFile: ".verify/traces/Traces.tla", atomically: true, encoding: .utf8)
}
