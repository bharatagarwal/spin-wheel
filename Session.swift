import SwiftUI
import QuartzCore

final class Ticker: NSObject {
    private let callback: (Double) -> Void
    private var link: CADisplayLink?
    private var last: CFTimeInterval?

    init(_ callback: @escaping (Double) -> Void) {
        self.callback = callback
        super.init()
        link = NSScreen.main?.displayLink(target: self, selector: #selector(step))
        link?.add(to: .main, forMode: .common)
    }

    /// The display link retains its target, so this must be called; dropping the Ticker isn't enough.
    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard let last else { return }
        callback(link.timestamp - last)
    }
}

final class SpinSession: Spinning {
    private struct Grip {
        var target: Double
        var fingerAngle: Double
        var samples: [(time: Date, angle: Double)] = []
    }

    private enum Motion {
        case held(Grip, Ticker)
        case coasting(Ticker)
        case finished
    }

    let slices: [Name]
    private(set) var released = Date()
    private var sim: WheelSim
    private var motion = Motion.finished
    private let onFrame: (WheelSim, _ held: Bool) -> Void
    private let onImpact: (WheelSim.Impact) -> Void
    private let onStop: (WheelSim) -> Void

    init(slices: [Name], clockwiseAngle: Double,
         onFrame: @escaping (WheelSim, _ held: Bool) -> Void,
         onImpact: @escaping (WheelSim.Impact) -> Void,
         onStop: @escaping (WheelSim) -> Void) {
        self.slices = slices
        self.sim = WheelSim(slices: slices.count, clockwiseAngle: clockwiseAngle)
        self.onFrame = onFrame
        self.onImpact = onImpact
        self.onStop = onStop
        motion = .coasting(Ticker { [weak self] dt in self?.frame(dt) })
    }

    func push(_ clockwiseSpeed: Double) {
        guard case .coasting = motion else { return }
        sim.push(clockwiseSpeed)
        released = Date()
    }

    func grab(at angle: Double) {
        guard case .coasting(let ticker) = motion else { return }
        motion = .held(Grip(target: sim.clockwiseAngle, fingerAngle: angle), ticker)
    }

    func drag(to angle: Double, at time: Date) {
        guard case .held(var g, let ticker) = motion else { return }
        let delta = remainder(angle - g.fingerAngle, 2 * .pi)
        g.fingerAngle += delta
        g.target += delta
        g.samples.append((time, g.fingerAngle))
        g.samples.removeAll { time.timeIntervalSince($0.time) > 0.1 }
        motion = .held(g, ticker)
    }

    func release(using rng: inout some RandomNumberGenerator) {
        guard case .held(let g, let ticker) = motion else { return }
        motion = .coasting(ticker)
        var flick = 0.0
        if let first = g.samples.first, let last = g.samples.last, last.time > first.time {
            flick = (last.angle - first.angle) / last.time.timeIntervalSince(first.time)
        }
        push(flickVelocity(flick, using: &rng))
    }

    private func frame(_ dt: Double) {
        let dt = min(dt, 1.0 / 20)
        let ticker: Ticker
        switch motion {
        case .held(let grip, let t):
            sim.drive((grip.target - sim.clockwiseAngle) / max(dt, 1.0 / 240))
            ticker = t
        case .coasting(let t):
            ticker = t
        case .finished:
            return
        }
        sim.advance(dt, onImpact: onImpact)
        let held = if case .held = motion { true } else { false }
        onFrame(sim, held)
        guard sim.stopped else { return }
        ticker.stop()
        motion = .finished
        onStop(sim)
    }
}

struct SpinLog {
    let path: String

    func record(_ session: SpinSession, winner: Name, simTime: Double) {
        let line = String(format: "spin slices=%d winner=%@ sim=%.2fs wall=%.2fs\n", session.slices.count, winner.text, simTime, Date().timeIntervalSince(session.released))
        if let h = FileHandle(forWritingAtPath: path) ?? (FileManager.default.createFile(atPath: path, contents: nil) ? FileHandle(forWritingAtPath: path) : nil) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        }
    }
}

final class Model: ObservableObject {
    @Published private(set) var standup = Standup<SpinSession>(team: Team.load())
    @Published var focus: Double = 0
    @Published var newName = ""

    private let sound = Sound()
    private let log = ProcessInfo.processInfo.environment["HOTPOTATO_VERIFY_LOG"].map(SpinLog.init)
    private var rng = SystemRandomNumberGenerator()

    var team: Team { standup.team }
    var turns: TurnOrder { standup.turns }
    var pose: WheelPose { standup.pose }
    var winner: Name? { standup.winner }
    var spinning: Bool { standup.spin != nil }

    func spin() {
        begin()?.push(spinVelocity(using: &rng))
    }

    func drag(to angle: Double, at time: Date) {
        if let session = standup.spin {
            session.drag(to: angle, at: time)
        } else if let session = begin() {
            session.grab(at: angle)
            session.drag(to: angle, at: time)
        }
    }

    func release() {
        standup.spin?.release(using: &rng)
    }

    private func begin() -> SpinSession? {
        standup.begin { [sound] slices, clockwiseAngle in
            SpinSession(
                slices: slices, clockwiseAngle: clockwiseAngle,
                onFrame: { [weak self] sim, held in self?.show(sim, held: held) },
                onImpact: { impact in sound.tick(speed: impact.speed, delay: impact.offset, reverse: impact.reverse) },
                onStop: { [weak self] sim in self?.finish(sim) })
        }
    }

    private func show(_ sim: WheelSim, held: Bool) {
        standup.pose = WheelPose(clockwiseAngle: sim.clockwiseAngle, rootFromVertical: sim.rootFromVertical, tipFromVertical: sim.tipFromVertical)
        if !held { focus = max(focus, min(1, max(0, (5 - abs(sim.clockwiseSpeed)) / 4))) }
    }

    private func finish(_ sim: WheelSim) {
        guard let session = standup.spin,
              let name = withAnimation(.spring(response: 0.5, dampingFraction: 0.6), { standup.finish(atSlice: sim.winner) })
        else { return }
        sound.chime()
        log?.record(session, winner: name, simTime: sim.time)
        withAnimation(.easeOut(duration: 0.8).delay(0.6)) { focus = 0 }
    }

    func reset() {
        standup.reset()
    }

    func add() {
        guard standup.add(newName) != nil else { return }
        team.save()
        newName = ""
    }

    func remove(_ name: Name) {
        standup.remove(name)
        team.save()
    }
}
