import SwiftUI
import AVFoundation

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

    func tick(intensity: Double) {
        guard let buffer = ticks.randomElement() else { return }
        play(buffer, volume: Float(0.15 + 0.3 * intensity), rate: 0.95 + 0.1 * intensity)
    }

    func chime() {
        if let reveal { play(reveal, volume: 0.7, rate: 1) }
    }

    private func play(_ buffer: AVAudioPCMBuffer, volume: Float, rate: Double) {
        if !engine.isRunning { try? engine.start() }
        let p = players[next]
        next = (next + 1) % players.count
        p.stop()
        p.volume = volume
        p.rate = Float(rate)
        p.scheduleBuffer(buffer)
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

let palette: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .blue, .indigo, .purple, .pink, .brown, .cyan]

final class Model: ObservableObject {
    @Published var namesRaw = UserDefaults.standard.string(forKey: "names") ?? "Alice\nBob\nCharlie\nDana" {
        didSet { UserDefaults.standard.set(namesRaw, forKey: "names") }
    }
    @Published var remaining: [String] = []
    @Published var done: [String] = []
    @Published var rotation: Double = 0
    @Published var flap: Double = 0
    @Published var focus: Double = 0
    @Published var spinning = false
    @Published var winner: String?
    @Published var newName = ""

    private var timer: Timer?
    private let sound = Sound()

    var names: [String] {
        namesRaw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func spin() {
        guard !spinning, !remaining.isEmpty else { return }
        if let w = winner { remaining.removeAll { $0 == w }; done.append(w); winner = nil }
        guard !remaining.isEmpty else { return }
        spinning = true

        let seg = 360.0 / Double(remaining.count)
        let start = rotation
        // Half the time, land just past a peg so the wheel teeters over it at the end.
        let landing = Bool.random() ? Double.random(in: 0.03...0.12) : Double.random(in: 0.15...0.85)
        let target = Double(Int.random(in: 0..<remaining.count)) + landing
        var end = start + 360 * Double(Int.random(in: 4...6))
        // Pointer sees wheel angle (270 - rotation); solve for the rotation that puts `target` under it.
        let current = ((270 - end).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        end += ((current - target * seg).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)

        let duration = Double.random(in: 3.2...4)
        let finalPeg = pegIndex(end, seg)
        var lastPeg = pegIndex(start, seg)
        var lastRotation = start
        var elapsed = 0.0
        var frozen = 0.0
        var flapVelocity = 0.0
        var last = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 1 / 120, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            let now = Date()
            let dt = min(now.timeIntervalSince(last), 1 / 30)
            last = now

            // Flapper is a damped spring, so it wobbles past centre after each peg.
            flapVelocity += (-420 * flap - 9 * flapVelocity) * dt
            flap += flapVelocity * dt

            if frozen > 0 {
                frozen -= dt
                return
            }
            elapsed += dt

            let p = min(1, elapsed / duration)
            // Quintic ease-out: fast start, long agonising crawl at the end.
            rotation = start + (end - start) * (1 - pow(1 - p, 5))
            focus = min(1, max(0, (elapsed - (duration - 1.2)) / 1))
            let speed = rotation - lastRotation
            lastRotation = rotation

            let peg = pegIndex(rotation, seg)
            if peg > lastPeg {
                lastPeg = peg
                flap = -min(38, 14 + speed * 6)
                flapVelocity = 0
                sound.tick(intensity: min(1, speed / 6))
                // Hold on the deciding peg, like a hit-pause.
                if peg == finalPeg { frozen = 0.18 }
            }

            if p >= 1 {
                t.invalidate()
                let a = ((270 - rotation).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    self.winner = self.remaining[min(Int(a / seg), self.remaining.count - 1)]
                    self.spinning = false
                }
                self.sound.chime()
                withAnimation(.easeOut(duration: 0.8).delay(0.6)) { self.focus = 0 }
                // Let the flapper finish wobbling.
                Timer.scheduledTimer(withTimeInterval: 1 / 120, repeats: true) { [weak self] t2 in
                    guard let self, abs(flap) > 0.05 || abs(flapVelocity) > 0.5 else { self?.flap = 0; return t2.invalidate() }
                    flapVelocity += (-420 * flap - 9 * flapVelocity) / 120
                    flap += flapVelocity / 120
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func pegIndex(_ r: Double, _ seg: Double) -> Int { Int(floor((r - 270) / seg)) }

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

    var body: some View {
        ZStack {
            Color.black.opacity(0.35 + 0.4 * m.focus)
                .ignoresSafeArea()

            HStack(spacing: 20) {
                VStack(spacing: 28) {
                    WheelAssembly(names: m.remaining, rotation: m.rotation, flap: m.flap)
                        .overlay {
                            Text(m.winner ?? " ")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32).padding(.vertical, 14)
                                .glassEffect(.regular, in: .capsule)
                                .opacity(m.winner == nil ? 0 : 1)
                                .scaleEffect(m.winner == nil ? 0.3 : 1)
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
                            Button("Reset") { m.reset() }
                                .disabled(m.spinning)
                                .buttonStyle(.glass)
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
                                    Spacer()
                                    Button { m.remove(name) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless)
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
                            .onSubmit(m.add)
                        Button { m.add() } label: { Image(systemName: "plus") }
                            .buttonStyle(.glass)
                    }
                }
                .padding(16)
                .frame(width: 250)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .opacity(1 - 0.6 * m.focus)
            }
            .padding(24)
        }
        .onAppear(perform: m.reset)
    }
}

struct WheelAssembly: View {
    let names: [String]
    let rotation: Double
    let flap: Double

    var body: some View {
        GeometryReader { g in
            let size = min(g.size.width, g.size.height)
            let rim = size * 0.035
            let face = size - rim * 2
            let flapW = size * 0.065
            let flapH = size * 0.13
            ZStack {
                Rim(rimWidth: rim)
                WheelFace(names: names)
                    .frame(width: face, height: face)
                    .rotationEffect(.degrees(rotation))
                Hub(size: size * 0.1)
                Flapper()
                    .frame(width: flapW, height: flapH)
                    .rotationEffect(.degrees(flap), anchor: UnitPoint(x: 0.5, y: 0.5 * flapW / flapH))
                    .position(x: size / 2, y: rim / 2 - flapW / 2 + flapH / 2)
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

struct Flapper: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .top) {
                Path { p in
                    p.move(to: CGPoint(x: w * 0.12, y: w * 0.5))
                    p.addLine(to: CGPoint(x: w * 0.88, y: w * 0.5))
                    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h), control: CGPoint(x: w * 0.7, y: h * 0.75))
                    p.addQuadCurve(to: CGPoint(x: w * 0.12, y: w * 0.5), control: CGPoint(x: w * 0.3, y: h * 0.75))
                }
                .fill(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .leading, endPoint: .trailing))
                .shadow(color: .black.opacity(0.55), radius: 3, x: 1, y: 3)
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.95), Color(white: 0.55)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: w * 0.6))
                    .frame(width: w, height: w)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
        }
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

                let pegR = max(3, r * 0.016)
                let pc = CGPoint(x: c.x + cos(a) * (r - pegR * 2.2), y: c.y + sin(a) * (r - pegR * 2.2))
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pegR + 1, y: pc.y - pegR + 2, width: pegR * 2, height: pegR * 2)), with: .color(.black.opacity(0.4)))
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pegR, y: pc.y - pegR, width: pegR * 2, height: pegR * 2)), with: .radialGradient(
                    Gradient(colors: [.white, Color(white: 0.6)]),
                    center: CGPoint(x: pc.x - pegR * 0.35, y: pc.y - pegR * 0.35), startRadius: 0, endRadius: pegR * 1.3))
            }
            ctx.stroke(disc, with: .color(.black.opacity(0.5)), lineWidth: 2)
        }
    }
}
