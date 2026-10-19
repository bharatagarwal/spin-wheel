import Foundation

struct Team {
    private(set) var names: [String]

    static func load() -> Team {
        let defaults = UserDefaults.standard
        let previousAppIDs = ["local.yourturn", "local.spinwheel"]
        let saved = defaults.string(forKey: "names")
            ?? previousAppIDs.lazy.compactMap { UserDefaults(suiteName: $0)?.string(forKey: "names") }.first
            ?? "Alice\nBob\nCharlie\nDana"
        let team = Team(names: saved.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        team.save()
        return team
    }

    func save() {
        UserDefaults.standard.set(names.joined(separator: "\n"), forKey: "names")
    }

    mutating func add(_ name: String) -> Bool {
        guard !name.isEmpty, !names.contains(name) else { return false }
        names.append(name)
        return true
    }

    mutating func remove(_ name: String) {
        names.removeAll { $0 == name }
    }
}

struct TurnOrder {
    private(set) var order: [String] = []
    private(set) var done: Set<String> = []
    private(set) var wheel: [String] = []

    init(shuffling names: [String] = []) {
        order = names.shuffled()
        wheel = order
    }

    var waiting: [String] { order.filter { !done.contains($0) } }

    mutating func add(_ name: String) {
        order.append(name)
        wheel.append(name)
    }

    mutating func addForNextSpin(_ name: String) {
        order.append(name)
    }

    mutating func remove(_ name: String) {
        order.removeAll { $0 == name }
        wheel.removeAll { $0 == name }
        done.remove(name)
    }

    mutating func beginSpin() -> [String] {
        wheel = waiting
        return wheel
    }

    mutating func markDone(_ name: String) {
        done.insert(name)
    }
}
