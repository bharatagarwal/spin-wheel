import Foundation

struct Name: Hashable, CustomStringConvertible {
    let text: String

    init?(_ typed: some StringProtocol) {
        text = String(typed).filter { !$0.unicodeScalars.allSatisfy(\.properties.isDefaultIgnorableCodePoint) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if text.isEmpty { return nil }
    }

    var description: String { text }
}

struct Team {
    private(set) var names: [Name] = []

    static let previousApps = ["local.yourturn", "local.spinwheel"].compactMap(UserDefaults.init(suiteName:))

    static func load(from defaults: UserDefaults = .standard, orFrom previous: [UserDefaults] = previousApps) -> Team {
        let saved = defaults.string(forKey: "names")
            ?? previous.lazy.compactMap { $0.string(forKey: "names") }.first
            ?? "Alice\nBob\nCharlie\nDana"
        var team = Team()
        for line in saved.split(whereSeparator: \.isNewline) {
            _ = team.add(line)
        }
        team.save(to: defaults)
        return team
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(names.map(\.text).joined(separator: "\n"), forKey: "names")
    }

    mutating func add(_ typed: some StringProtocol) -> Name? {
        guard let name = Name(typed), !names.contains(name) else { return nil }
        names.append(name)
        return name
    }

    mutating func remove(_ name: Name) {
        names.removeAll { $0 == name }
    }
}

struct TurnOrder {
    private(set) var order: [Name] = [] {
        didSet { assert(invariantsHold) }
    }
    private(set) var done: Set<Name> = [] {
        didSet { assert(invariantsHold) }
    }
    private(set) var wheel: [Name] = [] {
        didSet { assert(invariantsHold) }
    }

    var invariantsHold: Bool {
        Set(order).count == order.count && Set(wheel).count == wheel.count
            && Set(wheel).isSubset(of: order) && done.isSubset(of: order)
    }

    init(shuffling names: [Name] = []) {
        order = names.shuffled()
        wheel = order
    }

    var waiting: [Name] { order.filter { !done.contains($0) } }

    mutating func add(_ name: Name) {
        assert(!order.contains(name), "\(name) is already in the turn order")
        order.append(name)
        wheel.append(name)
    }

    mutating func addForNextSpin(_ name: Name) {
        assert(!order.contains(name), "\(name) is already in the turn order")
        order.append(name)
    }

    mutating func remove(_ name: Name) {
        done.remove(name)
        wheel.removeAll { $0 == name }
        order.removeAll { $0 == name }
    }

    mutating func beginSpin() -> [Name] {
        assert(!waiting.isEmpty, "a spin needs someone waiting")
        wheel = waiting
        return wheel
    }

    mutating func markDone(_ name: Name) {
        assert(wheel.contains(name) && !done.contains(name), "\(name) must be a slice who hasn't had a turn")
        done.insert(name)
    }
}
