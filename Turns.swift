import Foundation

struct Team {
    private(set) var names: [String]

    static let previousApps = ["local.yourturn", "local.spinwheel"].compactMap(UserDefaults.init(suiteName:))

    static func load(from defaults: UserDefaults = .standard, orFrom previous: [UserDefaults] = previousApps) -> Team {
        let saved = defaults.string(forKey: "names")
            ?? previous.lazy.compactMap { $0.string(forKey: "names") }.first
            ?? "Alice\nBob\nCharlie\nDana"
        var team = Team(names: [])
        for name in saved.split(whereSeparator: \.isNewline) {
            _ = team.add(String(name))
        }
        team.save(to: defaults)
        return team
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(names.joined(separator: "\n"), forKey: "names")
    }

    static func cleaned(_ typed: String) -> String {
        typed.filter { !$0.unicodeScalars.allSatisfy(\.properties.isDefaultIgnorableCodePoint) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    mutating func add(_ typed: String) -> String? {
        let name = Self.cleaned(typed)
        guard !name.isEmpty, !names.contains(name) else { return nil }
        names.append(name)
        return name
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
