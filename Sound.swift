import AVFoundation

final class Sound {
    private struct Mode {
        let freq: Double
        let decay: Double
        let gain: Double
    }

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
        let modes = [
            Mode(freq: 170 * jitter(), decay: 0.022, gain: 1.0),
            Mode(freq: 760 * jitter(), decay: 0.010, gain: 0.55),
            Mode(freq: 1290 * jitter(), decay: 0.007, gain: 0.4),
            Mode(freq: 2150 * jitter(), decay: 0.005, gain: 0.25),
            Mode(freq: 3400 * jitter(), decay: 0.003, gain: 0.12),
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
