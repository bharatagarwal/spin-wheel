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
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
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
        let player = players[next]
        next = (next + 1) % players.count
        player.stop()
        player.volume = volume
        player.rate = Float(rate)
        player.scheduleBuffer(buffer, at: when)
        player.play()
    }

    private func buffer(seconds: Double, _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        pcm.frameLength = frames
        let data = pcm.floatChannelData![0]
        for frame in 0..<Int(frames) { data[frame] = Float(sample(Double(frame) / format.sampleRate)) }
        return pcm
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
        let sampleRate = format.sampleRate
        var state = modes.map { _ in (0.0, 0.0) }
        var raw: [Double] = []
        for sampleIndex in 0..<Int(0.06 * sampleRate) {
            let time = Double(sampleIndex) / sampleRate
            let strike = time < 0.002 ? Double.random(in: -1...1) * (1 - time / 0.002) : 0
            var mixed = 0.0
            for (index, mode) in modes.enumerated() {
                let damping = exp(-1 / (mode.decay * sampleRate))
                let angularStep = 2 * .pi * mode.freq / sampleRate
                let out = 2 * damping * cos(angularStep) * state[index].0 - damping * damping * state[index].1 + strike * (1 - damping)
                state[index] = (out, state[index].0)
                mixed += out * mode.gain
            }
            raw.append(mixed)
        }
        let peak = raw.map(abs).max() ?? 1
        return buffer(seconds: 0.06) { time in raw[min(raw.count - 1, Int(time * sampleRate))] / peak }
    }

    private func makeChime() -> AVAudioPCMBuffer {
        func bell(_ frequency: Double, _ time: Double) -> Double {
            guard time >= 0 else { return 0 }
            let attack = min(1, time / 0.004)
            return attack * (sin(2 * .pi * frequency * time) * exp(-time * 3.2)
                + 0.4 * sin(2 * .pi * frequency * 2.76 * time) * exp(-time * 7)
                + 0.15 * sin(2 * .pi * frequency * 5.4 * time) * exp(-time * 12))
        }
        return buffer(seconds: 1.6) { time in 0.3 * (bell(659.25, time) + bell(987.77, time - 0.12)) }
    }
}
