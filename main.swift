import SwiftUI
import AVFoundation
import QuartzCore

@main
struct HotPotatoApp: App {
    var body: some Scene {
        WindowGroup("Hot Potato") {
            ContentView()
                .frame(minWidth: 820, minHeight: 600)
                .preferredColorScheme(.dark)
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

final class Sound {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var ticks: [AVAudioPCMBuffer] = []
    private var reveal: AVAudioPCMBuffer?

    init() {
        ticks = (0..<6).map { _ in makeTick() }
        reveal = makeChime()
        for _ in 0..<8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.8
        try? engine.start()
        // macOS stops the engine whenever the output device changes; bring it back.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            try? self?.engine.start()
        }
    }

    func tick(speed: Double, delay: Double, reverse: Bool) {
        guard let buffer = ticks.randomElement() else { return }
        let intensity = min(1, speed / 6)
        let when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay))
        play(buffer, volume: Float(0.08 + 0.37 * intensity), rate: (reverse ? 0.8 : 0.92) + 0.12 * intensity, at: when)
    }

    func chime() {
        if let reveal { play(reveal, volume: 0.7, rate: 1) }
    }

    private func play(_ buffer: AVAudioPCMBuffer, volume: Float, rate: Double, at when: AVAudioTime? = nil) {
        if !engine.isRunning { try? engine.start() }
        let p = players[next]
        next = (next + 1) % players.count
        p.stop()
        p.volume = volume
        p.rate = Float(rate)
        p.scheduleBuffer(buffer, at: when)
        p.play()
    }

    private func buffer(seconds: Double, _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * format.sampleRate)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        b.frameLength = n
        let data = b.floatChannelData![0]
        for i in 0..<Int(n) { data[i] = Float(sample(Double(i) / format.sampleRate)) }
        return b
    }

    private func makeTick() -> AVAudioPCMBuffer {
        let jitter = { Double.random(in: 0.93...1.07) }
        let modes: [(freq: Double, decay: Double, gain: Double)] = [
            (170 * jitter(), 0.022, 1.0),
            (760 * jitter(), 0.010, 0.55),
            (1290 * jitter(), 0.007, 0.4),
            (2150 * jitter(), 0.005, 0.25),
            (3400 * jitter(), 0.003, 0.12),
        ]
        let fs = format.sampleRate
        var state = modes.map { _ in (0.0, 0.0) }
        var raw: [Double] = []
        for i in 0..<Int(0.06 * fs) {
            let t = Double(i) / fs
            let strike = t < 0.002 ? Double.random(in: -1...1) * (1 - t / 0.002) : 0
            var y = 0.0
            for (k, m) in modes.enumerated() {
                let r = exp(-1 / (m.decay * fs))
                let w = 2 * .pi * m.freq / fs
                let out = 2 * r * cos(w) * state[k].0 - r * r * state[k].1 + strike * (1 - r)
                state[k] = (out, state[k].0)
                y += out * m.gain
            }
            raw.append(y)
        }
        let peak = raw.map(abs).max() ?? 1
        return buffer(seconds: 0.06) { t in raw[min(raw.count - 1, Int(t * fs))] / peak }
    }

    private func makeChime() -> AVAudioPCMBuffer {
        func bell(_ f: Double, _ t: Double) -> Double {
            guard t >= 0 else { return 0 }
            let attack = min(1, t / 0.004)
            return attack * (sin(2 * .pi * f * t) * exp(-t * 3.2)
                + 0.4 * sin(2 * .pi * f * 2.76 * t) * exp(-t * 7)
                + 0.15 * sin(2 * .pi * f * 5.4 * t) * exp(-t * 12))
        }
        return buffer(seconds: 1.6) { t in 0.3 * (bell(659.25, t) + bell(987.77, t - 0.12)) }
    }
}

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

let palette: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .blue, .indigo, .purple, .pink, .brown, .cyan]

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

struct WheelPose {
    var clockwiseAngle = 0.0
    var rootFromVertical = 0.0
    var tipFromVertical = 0.0
}

final class SpinSession {
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

    let slices: [String]
    private(set) var released = Date()
    private var sim: WheelSim
    private var motion = Motion.finished
    private let onFrame: (WheelSim, _ held: Bool) -> Void
    private let onImpact: (WheelSim.Impact) -> Void
    private let onStop: (WheelSim) -> Void

    init(slices: [String], clockwiseAngle: Double,
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

    func record(_ session: SpinSession, winner: String, simTime: Double) {
        let line = String(format: "spin slices=%d winner=%@ sim=%.2fs wall=%.2fs\n", session.slices.count, winner, simTime, Date().timeIntervalSince(session.released))
        if let h = FileHandle(forWritingAtPath: path) ?? (FileManager.default.createFile(atPath: path, contents: nil) ? FileHandle(forWritingAtPath: path) : nil) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        }
    }
}

final class Model: ObservableObject {
    enum Phase {
        case idle(winner: String?)
        case spinning(SpinSession)
    }

    @Published private(set) var team = Team.load() {
        didSet { team.save() }
    }
    @Published private(set) var turns = TurnOrder()
    @Published private(set) var pose = WheelPose()
    @Published private(set) var phase = Phase.idle(winner: nil)
    @Published var focus: Double = 0
    @Published var newName = ""

    private let sound = Sound()
    private let log = ProcessInfo.processInfo.environment["HOTPOTATO_VERIFY_LOG"].map(SpinLog.init)
    private var rng = SystemRandomNumberGenerator()

    var spinning: Bool {
        if case .spinning = phase { true } else { false }
    }

    var winner: String? {
        if case .idle(let winner) = phase { winner } else { nil }
    }

    func spin() {
        begin()?.push(spinVelocity(using: &rng))
    }

    func drag(to angle: Double, at time: Date) {
        switch phase {
        case .idle:
            guard let session = begin() else { return }
            session.grab(at: angle)
            session.drag(to: angle, at: time)
        case .spinning(let session):
            session.drag(to: angle, at: time)
        }
    }

    func release() {
        guard case .spinning(let session) = phase else { return }
        session.release(using: &rng)
    }

    private func begin() -> SpinSession? {
        guard case .idle = phase, !turns.waiting.isEmpty else { return nil }
        let session = SpinSession(
            slices: turns.beginSpin(), clockwiseAngle: pose.clockwiseAngle,
            onFrame: { [weak self] sim, held in self?.show(sim, held: held) },
            onImpact: { [sound] impact in sound.tick(speed: impact.speed, delay: impact.offset, reverse: impact.reverse) },
            onStop: { [weak self] sim in self?.finish(sim) })
        phase = .spinning(session)
        return session
    }

    private func show(_ sim: WheelSim, held: Bool) {
        pose = WheelPose(clockwiseAngle: sim.clockwiseAngle, rootFromVertical: sim.rootFromVertical, tipFromVertical: sim.tipFromVertical)
        if !held { focus = max(focus, min(1, max(0, (5 - abs(sim.clockwiseSpeed)) / 4))) }
    }

    private func finish(_ sim: WheelSim) {
        guard case .spinning(let session) = phase else { return }
        let name = session.slices[sim.winner]
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            turns.markDone(name)
            phase = .idle(winner: name)
        }
        sound.chime()
        log?.record(session, winner: name, simTime: sim.time)
        withAnimation(.easeOut(duration: 0.8).delay(0.6)) { focus = 0 }
    }

    func reset() {
        guard case .idle = phase else { return }
        turns = TurnOrder(shuffling: team.names)
        phase = .idle(winner: nil)
    }

    func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard team.add(name) else { return }
        switch phase {
        case .idle: turns.add(name)
        case .spinning: turns.addForNextSpin(name)
        }
        newName = ""
    }

    func remove(_ name: String) {
        guard case .idle(let winner) = phase else { return }
        team.remove(name)
        turns.remove(name)
        if winner == name { phase = .idle(winner: nil) }
    }
}

struct ContentView: View {
    @StateObject private var m = Model()
    @FocusState private var typingName: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35 + 0.4 * m.focus)
                .ignoresSafeArea()

            HStack(spacing: 20) {
                VStack(spacing: 28) {
                    WheelAssembly(names: m.turns.wheel, pose: m.pose,
                                  onDrag: m.drag(to:at:), onRelease: m.release)
                        .accessibilityElement()
                        .accessibilityIdentifier("wheel")
                        .accessibilityValue(m.spinning ? "spinning" : "idle")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { m.spin() }
                        .overlay {
                            Text(m.winner ?? " ")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32).padding(.vertical, 14)
                                .glassEffect(.regular, in: .capsule)
                                .opacity(m.winner == nil ? 0 : 1)
                                .scaleEffect(m.winner == nil ? 0.3 : 1)
                                .accessibilityIdentifier("winner")
                        }
                        .scaleEffect(1 + 0.06 * m.focus)
                        .zIndex(1)
                        .onTapGesture { m.spin() }

                    GlassEffectContainer {
                        HStack(spacing: 12) {
                            Button("Spin") { m.spin() }
                                .keyboardShortcut(.space, modifiers: [])
                                .disabled(m.spinning || m.turns.waiting.isEmpty)
                                .buttonStyle(.glassProminent)
                                .accessibilityIdentifier("spin")
                            Button("Reset") { m.reset() }
                                .disabled(m.spinning)
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("reset")
                        }
                        .controlSize(.extraLarge)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Team").font(.title3.bold())
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(m.team.names, id: \.self) { name in
                                HStack {
                                    Text(name)
                                        .strikethrough(m.turns.done.contains(name))
                                        .opacity(m.turns.done.contains(name) ? 0.5 : 1)
                                        .accessibilityIdentifier("member-\(name)")
                                        .accessibilityValue(m.turns.done.contains(name) ? "done" : "waiting")
                                    Spacer()
                                    Button { m.remove(name) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless)
                                        .disabled(m.spinning)
                                        .accessibilityIdentifier("remove-\(name)")
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            }
                        }
                    }
                    HStack {
                        TextField("Add name", text: $m.newName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                            .focused($typingName)
                            .accessibilityIdentifier("name-field")
                            .onSubmit(m.add)
                        Button { m.add() } label: { Image(systemName: "plus") }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("add")
                    }
                }
                .padding(16)
                .frame(width: 250)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .opacity(1 - 0.6 * m.focus)
            }
            .padding(24)
        }
        .onAppear {
            m.reset()
            // macOS focuses the text field at launch, which would swallow Space.
            DispatchQueue.main.async { typingName = false }
        }
    }
}

struct WheelAssembly: View {
    private let hubDeadZone = 0.12
    let names: [String]
    let pose: WheelPose
    var onDrag: (Double, Date) -> Void = { _, _ in }
    var onRelease: () -> Void = {}

    var body: some View {
        GeometryReader { g in
            let size = min(g.size.width, g.size.height)
            let rim = size * 0.035
            let face = size - rim * 2
            ZStack {
                Rim(rimWidth: rim)
                WheelFace(names: names)
                    .frame(width: face, height: face)
                    .rotationEffect(.radians(pose.clockwiseAngle))
                Hub(size: size * 0.1)
                Flapper(pose: pose, faceRadius: face / 2)
            }
            .frame(width: size, height: size)
            .position(x: g.size.width / 2, y: g.size.height / 2)
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { v in
                    let x = v.location.x - g.size.width / 2, y = v.location.y - g.size.height / 2
                    if x * x + y * y > pow(size * hubDeadZone, 2) { onDrag(atan2(y, x), v.time) }
                }
                .onEnded { _ in onRelease() })
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }
}

struct Rim: View {
    let rimWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            ctx.fill(Path(ellipseIn: rect), with: .linearGradient(
                Gradient(colors: [Color(white: 0.85), Color(white: 0.45), Color(white: 0.7), Color(white: 0.3)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)), with: .color(.white.opacity(0.3)), lineWidth: 1)
            let inner = rect.insetBy(dx: rimWidth, dy: rimWidth)
            ctx.fill(Path(ellipseIn: inner.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(0.4)))

        }
    }
}

struct Hub: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.95), Color(white: 0.7), Color(white: 0.4)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            Circle().stroke(.white.opacity(0.6), lineWidth: 1).padding(1)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

struct Flapper: View {
    let pose: WheelPose
    let faceRadius: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let r = faceRadius
            let points = WheelRadii.flapper(rootFromVertical: pose.rootFromVertical, tipFromVertical: pose.tipFromVertical)
            func onScreen(_ p: YDownPoint) -> CGPoint { CGPoint(x: size.width / 2 + p.x * r, y: size.height / 2 + p.y * r) }
            let pivot = onScreen(points.pivot), joint = onScreen(points.joint), end = onScreen(points.tip)
            func direction(_ a: CGPoint, _ b: CGPoint) -> CGVector {
                let length = hypot(b.x - a.x, b.y - a.y)
                return CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
            }
            let rootDir = direction(pivot, joint), tipDir = direction(joint, end)
            let tipW = WheelRadii.armRadius * r, rootW = tipW * 2.4, midW = (tipW + rootW) / 2
            func side(_ p: CGPoint, _ d: CGVector, _ w: CGFloat) -> CGPoint { CGPoint(x: p.x - d.dy * w, y: p.y + d.dx * w) }
            let jointDir = CGVector(dx: (rootDir.dx + tipDir.dx) / 2, dy: (rootDir.dy + tipDir.dy) / 2)

            var p = Path()
            p.move(to: side(pivot, rootDir, rootW))
            p.addLine(to: side(joint, jointDir, midW))
            p.addLine(to: side(end, tipDir, tipW))
            p.addArc(center: end, radius: tipW, startAngle: .radians(pose.tipFromVertical + .pi), endAngle: .radians(pose.tipFromVertical), clockwise: true)
            p.addLine(to: side(joint, jointDir, -midW))
            p.addLine(to: side(pivot, rootDir, -rootW))
            p.closeSubpath()
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2))
                l.fill(p, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.75)]),
                                                startPoint: CGPoint(x: pivot.x - rootW, y: pivot.y), endPoint: CGPoint(x: pivot.x + rootW, y: pivot.y)))
            }
            let capR = rootW * 1.5
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.5), radius: 1.5, y: 1))
                l.fill(Path(ellipseIn: CGRect(x: pivot.x - capR, y: pivot.y - capR, width: capR * 2, height: capR * 2)),
                       with: .radialGradient(Gradient(colors: [Color(white: 0.95), Color(white: 0.55)]),
                                             center: CGPoint(x: pivot.x - capR * 0.3, y: pivot.y - capR * 0.3), startRadius: 0, endRadius: capR * 1.2))
            }
        }
        .allowsHitTesting(false)
    }
}

struct WheelFace: View {
    let names: [String]

    var body: some View {
        Canvas { ctx, size in
            let r = size.width / 2
            let c = CGPoint(x: r, y: r)
            let disc = Path(ellipseIn: CGRect(origin: .zero, size: size))
            guard !names.isEmpty else {
                ctx.fill(disc, with: .color(Color(white: 0.2)))
                return
            }
            for i in names.indices {
                var p = Path()
                p.move(to: c)
                p.addArc(center: c, radius: r, startAngle: .radians(WheelRadii.sliceAngle(i, of: names.count)), endAngle: .radians(WheelRadii.sliceAngle(i + 1, of: names.count)), clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(palette[i % palette.count]))
            }
            ctx.fill(disc, with: .radialGradient(Gradient(colors: [.white.opacity(0.08), .clear, .black.opacity(0.18)]),
                                                 center: c, startRadius: 0, endRadius: r))

            for (i, name) in names.enumerated() {
                var t = ctx
                t.translateBy(x: c.x, y: c.y)
                t.rotate(by: .radians((WheelRadii.sliceAngle(i, of: names.count) + WheelRadii.sliceAngle(i + 1, of: names.count)) / 2))
                let fontSize = min(24, max(11, r / CGFloat(max(names.count, 4)) * 0.9))
                let text = Text(name).font(.system(size: fontSize, weight: .heavy, design: .rounded)).foregroundColor(.white)
                t.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1))
                    l.draw(text, at: CGPoint(x: r * 0.82, y: 0), anchor: .trailing)
                }
            }

            for i in 0..<names.count {
                let a = WheelRadii.sliceAngle(i, of: names.count)
                var line = Path()
                line.move(to: c)
                line.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                ctx.stroke(line, with: .color(.white.opacity(0.7)), lineWidth: 1.5)

                let pegR = r * WheelRadii.pegRadius
                let peg = WheelRadii.peg(i, of: names.count)
                let pc = CGPoint(x: c.x + peg.x * r, y: c.y + peg.y * r)
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pegR + 1, y: pc.y - pegR + 2, width: pegR * 2, height: pegR * 2)), with: .color(.black.opacity(0.4)))
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pegR, y: pc.y - pegR, width: pegR * 2, height: pegR * 2)), with: .radialGradient(
                    Gradient(colors: [.white, Color(white: 0.6)]),
                    center: CGPoint(x: pc.x - pegR * 0.35, y: pc.y - pegR * 0.35), startRadius: 0, endRadius: pegR * 1.3))
            }
            ctx.stroke(disc, with: .color(.black.opacity(0.5)), lineWidth: 2)
        }
    }
}
