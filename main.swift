import SwiftUI
import AVFoundation
import QuartzCore

@main
struct SpinWheelApp: App {
    var body: some Scene {
        WindowGroup("Standup Wheel") {
            ContentView()
                .frame(minWidth: 820, minHeight: 600)
                .preferredColorScheme(.dark)
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

/// Synthesised once at launch; no audio files or system sounds.
final class Sound {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var ticks: [AVAudioPCMBuffer] = []
    private var reveal: AVAudioPCMBuffer?

    init() {
        // A few variants so fast ticks don't sound machine-gun identical.
        ticks = (0..<6).map { _ in makeTick() }
        reveal = makeChime()
        // Round-robin voices so overlapping ticks don't queue behind each other.
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

    /// A peg strike. Loudness and brightness follow the real impact speed; `delay` keeps
    /// strikes spaced as they happened inside the frame; a roll-back strike sounds duller.
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

    // Flapper snapping off a peg: a ~2 ms strike exciting a few heavily damped modes,
    // one low "knock" from the wheel's wooden body plus the flapper's own inharmonic ring.
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

    // Two soft bell notes (E5 then B5), each with a couple of inharmonic partials.
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

/// Calls back once per display refresh with the real elapsed time.
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

final class Model: ObservableObject {
    @Published var namesRaw = UserDefaults.standard.string(forKey: "names") ?? "Alice\nBob\nCharlie\nDana" {
        didSet { UserDefaults.standard.set(namesRaw, forKey: "names") }
    }
    @Published var remaining: [String] = []
    @Published var done: [String] = []
    @Published var rotation: Double = 0      // radians, clockwise
    @Published var flapper: Double = 0       // radians, 0 = hanging straight down
    @Published var focus: Double = 0
    @Published var spinning = false
    @Published var winner: String?
    @Published var newName = ""

    private var sim: WheelSim?
    private var ticker: Ticker?
    private let sound = Sound()
    private var spinStarted = Date()
    /// Set SPINWHEEL_VERIFY_LOG=<path> to append one line per finished spin (used by verification).
    private let verifyLog = ProcessInfo.processInfo.environment["SPINWHEEL_VERIFY_LOG"]

    var names: [String] {
        namesRaw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func spin() {
        guard !spinning, !remaining.isEmpty else { return }
        if let w = winner { remaining.removeAll { $0 == w }; done.append(w); winner = nil }
        guard !remaining.isEmpty else { return }
        spinning = true

        var sim = WheelSim(slices: remaining.count, theta: rotation)
        sim.push(spinVelocity())
        self.sim = sim
        spinStarted = Date()
        ticker?.stop()
        ticker = Ticker { [weak self] dt in self?.frame(dt) }
    }

    private func frame(_ dt: Double) {
        guard var sim else { return }
        sim.advance(min(dt, 1.0 / 20)) { offset, speed, reverse in
            sound.tick(speed: speed, delay: offset, reverse: reverse)
        }
        self.sim = sim
        rotation = sim.theta
        flapper = sim.phi
        // Close in on the wheel as it runs out of speed.
        focus = max(focus, min(1, max(0, (5 - abs(sim.omega)) / 4)))

        guard sim.stopped else { return }
        ticker?.stop()
        ticker = nil
        self.sim = nil
        let index = sim.winner
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            winner = remaining[index]
            spinning = false
        }
        sound.chime()
        if let verifyLog {
            let line = String(format: "spin slices=%d winner=%@ sim=%.2fs wall=%.2fs\n", remaining.count, remaining[index], sim.time, Date().timeIntervalSince(spinStarted))
            if let h = FileHandle(forWritingAtPath: verifyLog) ?? (FileManager.default.createFile(atPath: verifyLog, contents: nil) ? FileHandle(forWritingAtPath: verifyLog) : nil) {
                h.seekToEndOfFile()
                h.write(line.data(using: .utf8)!)
                try? h.close()
            }
        }
        withAnimation(.easeOut(duration: 0.8).delay(0.6)) { focus = 0 }
    }

    func reset() {
        guard !spinning else { return }
        remaining = names.shuffled()
        done = []
        winner = nil
    }

    func add() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !names.contains(n) else { return }
        namesRaw = (names + [n]).joined(separator: "\n")
        if !spinning { remaining.append(n) }
        newName = ""
    }

    func remove(_ name: String) {
        namesRaw = names.filter { $0 != name }.joined(separator: "\n")
        if !spinning { remaining.removeAll { $0 == name } }
        if winner == name { winner = nil }
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
                    WheelAssembly(names: m.remaining, rotation: m.rotation, flapper: m.flapper)
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
                                .disabled(m.spinning || m.remaining.isEmpty)
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
                            ForEach(m.names, id: \.self) { name in
                                HStack {
                                    Text(name)
                                        .strikethrough(m.done.contains(name))
                                        .opacity(m.done.contains(name) ? 0.5 : 1)
                                        .accessibilityIdentifier("member-\(name)")
                                        .accessibilityValue(m.done.contains(name) ? "done" : "waiting")
                                    Spacer()
                                    Button { m.remove(name) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless)
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
    let names: [String]
    let rotation: Double
    let flapper: Double

    var body: some View {
        GeometryReader { g in
            let size = min(g.size.width, g.size.height)
            let rim = size * 0.035
            let face = size - rim * 2
            ZStack {
                Rim(rimWidth: rim)
                WheelFace(names: names)
                    .frame(width: face, height: face)
                    .rotationEffect(.radians(rotation))
                Hub(size: size * 0.1)
                Flapper(angle: flapper, faceRadius: face / 2)
            }
            .frame(width: size, height: size)
            .position(x: g.size.width / 2, y: g.size.height / 2)
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

/// Drawn from the same `Geometry` the simulation collides against.
struct Flapper: View {
    let angle: Double
    let faceRadius: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let r = faceRadius
            let pivot = CGPoint(x: size.width / 2, y: size.height / 2 - Geometry.pivot * r)
            let len = Geometry.armLength * r
            let tipW = Geometry.armRadius * r
            let rootW = tipW * 2.4
            var arm = ctx
            arm.translateBy(x: pivot.x, y: pivot.y)
            arm.rotate(by: .radians(angle))
            var p = Path()
            p.move(to: CGPoint(x: -rootW, y: 0))
            p.addLine(to: CGPoint(x: rootW, y: 0))
            p.addLine(to: CGPoint(x: tipW, y: len))
            p.addArc(center: CGPoint(x: 0, y: len), radius: tipW, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
            arm.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2))
                l.fill(p, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.75)]),
                                                startPoint: CGPoint(x: -rootW, y: 0), endPoint: CGPoint(x: rootW, y: 0)))
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
            let seg = 360.0 / Double(names.count)
            for i in names.indices {
                var p = Path()
                p.move(to: c)
                p.addArc(center: c, radius: r, startAngle: .degrees(Double(i) * seg), endAngle: .degrees(Double(i + 1) * seg), clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(palette[i % palette.count]))
            }
            // Curvature shading: lighter towards the hub, darker at the rim.
            ctx.fill(disc, with: .radialGradient(Gradient(colors: [.white.opacity(0.08), .clear, .black.opacity(0.18)]),
                                                 center: c, startRadius: 0, endRadius: r))

            for (i, name) in names.enumerated() {
                var t = ctx
                t.translateBy(x: c.x, y: c.y)
                t.rotate(by: .degrees((Double(i) + 0.5) * seg))
                let fontSize = min(24, max(11, r / CGFloat(max(names.count, 4)) * 0.9))
                let text = Text(name).font(.system(size: fontSize, weight: .heavy, design: .rounded)).foregroundColor(.white)
                t.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1))
                    l.draw(text, at: CGPoint(x: r * 0.82, y: 0), anchor: .trailing)
                }
            }

            for i in 0..<names.count {
                let a = Double(i) * seg * .pi / 180
                var line = Path()
                line.move(to: c)
                line.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                ctx.stroke(line, with: .color(.white.opacity(0.7)), lineWidth: 1.5)

                let pegR = r * Geometry.pegRadius
                let pc = CGPoint(x: c.x + cos(a) * r * Geometry.pegCircle, y: c.y + sin(a) * r * Geometry.pegCircle)
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pegR + 1, y: pc.y - pegR + 2, width: pegR * 2, height: pegR * 2)), with: .color(.black.opacity(0.4)))
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pegR, y: pc.y - pegR, width: pegR * 2, height: pegR * 2)), with: .radialGradient(
                    Gradient(colors: [.white, Color(white: 0.6)]),
                    center: CGPoint(x: pc.x - pegR * 0.35, y: pc.y - pegR * 0.35), startRadius: 0, endRadius: pegR * 1.3))
            }
            ctx.stroke(disc, with: .color(.black.opacity(0.5)), lineWidth: 2)
        }
    }
}
