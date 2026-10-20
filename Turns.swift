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

protocol Spinning {
    var slices: [Name] { get }
}

struct Standup<Spin: Spinning> {
    enum Phase {
        case idle(winner: Name?)
        case spinning(Spin)
    }

    private(set) var team: Team
    private(set) var turns: TurnOrder
    private(set) var phase = Phase.idle(winner: nil)
    var pose = WheelPose()

    init(team: Team) {
        self.team = team
        turns = TurnOrder(shuffling: team.names)
    }

    var spin: Spin? {
        if case .spinning(let spin) = phase { spin } else { nil }
    }

    var winner: Name? {
        if case .idle(let winner) = phase { winner } else { nil }
    }

    mutating func begin(_ start: (_ slices: [Name], _ clockwiseAngle: Double) -> Spin) -> Spin? {
        guard case .idle = phase, !turns.waiting.isEmpty else { return nil }
        let spin = start(turns.beginSpin(), pose.clockwiseAngle)
        phase = .spinning(spin)
        return spin
    }

    mutating func finish(atSlice slice: Int) -> Name? {
        guard let spin else { return nil }
        let name = spin.slices[slice]
        turns.markDone(name)
        phase = .idle(winner: name)
        return name
    }

    mutating func reset() {
        guard case .idle = phase else { return }
        turns = TurnOrder(shuffling: team.names)
        phase = .idle(winner: nil)
    }

    mutating func add(_ typed: some StringProtocol) -> Name? {
        guard let name = team.add(typed) else { return nil }
        switch phase {
        case .idle: keepingTheWinnerUnderTheFlapper { $0.add(name) }
        case .spinning: turns.addForNextSpin(name)
        }
        return name
    }

    mutating func remove(_ name: Name) {
        guard case .idle(let winner) = phase else { return }
        team.remove(name)
        keepingTheWinnerUnderTheFlapper { $0.remove(name) }
        if winner == name { phase = .idle(winner: nil) }
    }

    private mutating func keepingTheWinnerUnderTheFlapper(_ change: (inout TurnOrder) -> Void) {
        let before = turns.wheel
        change(&turns)
        guard let winner, let old = before.firstIndex(of: winner), let new = turns.wheel.firstIndex(of: winner) else { return }
        pose.clockwiseAngle = pose.clockwiseAngle(keepingSlice: old, of: before.count, underTheFlapperAs: new, of: turns.wheel.count)
    }
}
