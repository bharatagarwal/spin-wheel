import Foundation

typealias YDownPoint = (x: Double, y: Double)

enum WheelRadii {
    static let pegCircle = 0.93
    static let pegRadius = 0.016
    static let pivot = 1.06
    static let armLength = 0.115
    static let segmentLength = armLength / 2
    static let armRadius = 0.010
}

struct WheelSim {
    struct Params {
        var wheelInertia = 1.0
        var kineticFriction = 1.3
        var staticFriction = 1.8
        var viscousDrag = 0.013
        var airDrag = 0.00065
        var hingeInertia = 0.0007
        var hingeStiffness = 5.0
        var hingeDampingRatio = 0.45
        var bendStiffness = 12.0
        var bendDampingRatio = 0.15
        var contactStiffness = 3e5
        var contactDamping = 0.6
        var contactFriction = 0.15

        func scaled(forSlices slices: Int) -> Params {
            let scale = 5 / Double(max(slices, 2))
            var p = self
            p.hingeStiffness *= scale
            p.bendStiffness *= scale
            p.hingeInertia *= scale
            return p
        }
    }

    struct Impact {
        let offset: Double
        let speed: Double
        let reverse: Bool
    }

    let slices: Int
    let segment: Double
    var params: Params

    private(set) var clockwiseAngle: Double
    private(set) var clockwiseSpeed = 0.0
    private(set) var rootFromVertical = 0.0
    private(set) var rootRate = 0.0
    private(set) var tipFromVertical = 0.0
    private(set) var tipRate = 0.0
    private(set) var time = 0.0
    private(set) var stopped = false
    private(set) var rolledBack = false
    private(set) var peakRoot = 0.0
    private(set) var peakBend = 0.0
    private(set) var peakTip = 0.0

    static let step = 1.0 / 8000
    private var carry = 0.0
    private var touching = false
    private var still = 0.0
    private var stuck = true
    private var fingerSpeed: Double?
    private var direction = 1.0

    init(slices: Int, clockwiseAngle: Double = 0, params: Params = Params()) {
        self.slices = slices
        self.segment = 2 * .pi / Double(slices)
        self.clockwiseAngle = clockwiseAngle
        self.params = params.scaled(forSlices: slices)
    }

    mutating func push(_ angularVelocity: Double) {
        clockwiseSpeed = angularVelocity
        direction = angularVelocity < 0 ? -1 : 1
        fingerSpeed = nil
        stuck = false
        stopped = false
    }

    mutating func drive(_ angularVelocity: Double) {
        fingerSpeed = angularVelocity
        stuck = false
        stopped = false
    }

    mutating func advance(_ dt: Double, onImpact: (Impact) -> Void = { _ in }) {
        carry += dt
        var elapsed = 0.0
        while carry >= Self.step, !stopped {
            if let speed = substep() { onImpact(Impact(offset: elapsed, speed: speed, reverse: clockwiseSpeed * direction < 0)) }
            carry -= Self.step
            elapsed += Self.step
        }
    }

    var winner: Int {
        let t = points.tip
        var a = (atan2(t.y, t.x) - clockwiseAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return min(Int(a / segment), slices - 1)
    }

    private var points: (joint: YDownPoint, tip: YDownPoint) {
        let segmentLength = WheelRadii.segmentLength
        let joint = (x: -sin(rootFromVertical) * segmentLength, y: -WheelRadii.pivot + cos(rootFromVertical) * segmentLength)
        return (joint, (x: joint.x - sin(tipFromVertical) * segmentLength, y: joint.y + cos(tipFromVertical) * segmentLength))
    }

    private mutating func substep() -> Double? {
        let p = params
        let a = WheelRadii.segmentLength, b = a
        let segmentMass = p.hingeInertia / (5 * a * a)
        let rootDamping = 2 * p.hingeDampingRatio * (p.hingeStiffness * p.hingeInertia).squareRoot()
        let bendDamping = 2 * p.bendDampingRatio * (p.bendStiffness * segmentMass * b * b).squareRoot()
        let bend = p.bendStiffness * (tipFromVertical - rootFromVertical) + bendDamping * (tipRate - rootRate)
        var forceRoot = -p.hingeStiffness * rootFromVertical - rootDamping * rootRate + bend
        var forceTip = -bend

        let pivot: YDownPoint = (x: 0.0, y: -WheelRadii.pivot)
        let joint = points.joint
        let rootDir = (x: -sin(rootFromVertical), y: cos(rootFromVertical)), tipDir = (x: -sin(tipFromVertical), y: cos(tipFromVertical))
        var contactTorque = 0.0
        var impact: Double?
        var inContact = false

        let pegBeforePointer = Int(floor((-.pi / 2 - clockwiseAngle) / segment))
        for i in pegBeforePointer...(pegBeforePointer + 1) {
            let angle = clockwiseAngle + Double(i) * segment
            let cx = WheelRadii.pegCircle * cos(angle), cy = WheelRadii.pegCircle * sin(angle)

            var best: (depth: Double, q: YDownPoint, rootJacobian: YDownPoint, tipJacobian: YDownPoint)?
            for outer in [false, true] {
                let start = outer ? joint : pivot
                let dir = outer ? tipDir : rootDir
                let len = outer ? b : a
                let s = min(max((cx - start.x) * dir.x + (cy - start.y) * dir.y, 0), len)
                let q = (x: start.x + s * dir.x, y: start.y + s * dir.y)
                let depth = WheelRadii.pegRadius + WheelRadii.armRadius - ((cx - q.x) * (cx - q.x) + (cy - q.y) * (cy - q.y)).squareRoot()
                let rootJacobian = outer ? (x: -a * cos(rootFromVertical), y: -a * sin(rootFromVertical)) : (x: -s * cos(rootFromVertical), y: -s * sin(rootFromVertical))
                let tipJacobian = outer ? (x: -s * cos(tipFromVertical), y: -s * sin(tipFromVertical)) : (x: 0.0, y: 0.0)
                if depth > 0, depth > best?.depth ?? 0 { best = (depth, q, rootJacobian, tipJacobian) }
            }
            guard let c = best else { continue }
            inContact = true

            let sx = cx - c.q.x, sy = cy - c.q.y
            let dist = max((sx * sx + sy * sy).squareRoot(), 1e-9)
            let nx = sx / dist, ny = sy / dist
            let tx = -ny, ty = nx
            let vx = -clockwiseSpeed * cy - (c.rootJacobian.x * rootRate + c.tipJacobian.x * tipRate)
            let vy = clockwiseSpeed * cx - (c.rootJacobian.y * rootRate + c.tipJacobian.y * tipRate)
            let vn = vx * nx + vy * ny
            let vt = vx * tx + vy * ty
            if !touching, vn < 0 { impact = -vn }

            let normal = max(0, p.contactStiffness * pow(c.depth, 1.5) * (1 - 1.5 * p.contactDamping * vn))
            let friction = -p.contactFriction * normal * tanh(vt / 0.02)
            let fx = normal * nx + friction * tx, fy = normal * ny + friction * ty
            contactTorque += cx * fy - cy * fx
            forceRoot -= c.rootJacobian.x * fx + c.rootJacobian.y * fy
            forceTip -= c.tipJacobian.x * fx + c.tipJacobian.y * fy
        }
        touching = inContact

        stepFlapper(forceRoot: forceRoot, forceTip: forceTip, segmentMass: segmentMass)
        stepWheel(contactTorque: contactTorque)
        updateStopped()
        return impact
    }

    private mutating func stepFlapper(forceRoot: Double, forceTip: Double, segmentMass: Double) {
        let h = Self.step
        let a = WheelRadii.segmentLength, b = a
        let cosD = cos(rootFromVertical - tipFromVertical), sinD = sin(rootFromVertical - tipFromVertical)
        let m11 = 2 * segmentMass * a * a, m12 = segmentMass * a * b * cosD, m22 = segmentMass * b * b
        let r1 = forceRoot - segmentMass * a * b * sinD * tipRate * tipRate
        let r2 = forceTip + segmentMass * a * b * sinD * rootRate * rootRate
        let det = m11 * m22 - m12 * m12
        rootRate += (r1 * m22 - m12 * r2) / det * h
        tipRate += (m11 * r2 - m12 * r1) / det * h
        rootFromVertical += rootRate * h
        tipFromVertical += tipRate * h
    }

    private mutating func stepWheel(contactTorque: Double) {
        let p = params
        let h = Self.step
        if let fingerSpeed {
            clockwiseSpeed = fingerSpeed
        } else {
            if stuck, abs(contactTorque) > p.staticFriction { stuck = false }
            if !stuck {
                let sliding = clockwiseSpeed != 0 ? (clockwiseSpeed > 0 ? 1.0 : -1.0) : (contactTorque > 0 ? 1.0 : -1.0)
                let torque = contactTorque - p.kineticFriction * sliding - p.viscousDrag * clockwiseSpeed - p.airDrag * clockwiseSpeed * abs(clockwiseSpeed)
                let next = clockwiseSpeed + torque / p.wheelInertia * h
                if next * sliding <= 0 {
                    clockwiseSpeed = 0
                    stuck = abs(contactTorque) <= p.staticFriction
                } else {
                    clockwiseSpeed = next
                }
            }
        }
        clockwiseAngle += clockwiseSpeed * h
        time += h
        if clockwiseSpeed * direction < -0.05 { rolledBack = true }
        peakRoot = max(peakRoot, abs(rootFromVertical))
        peakBend = max(peakBend, abs(tipFromVertical - rootFromVertical))
        peakTip = max(peakTip, abs(tipFromVertical))
    }

    private mutating func updateStopped() {
        let h = Self.step
        if fingerSpeed == nil, stuck, abs(rootRate) < 0.3, abs(tipRate) < 0.6 {
            still += h
            if still > 0.15 { stopped = true }
        } else {
            still = 0
        }
        if time > 30 { stopped = true }
    }
}

let buttonSpinSpeeds = 9.0...11.0
let flickSpinSpeeds = 9.0...12.0

func spinVelocity() -> Double { Double.random(in: buttonSpinSpeeds) }

func flickVelocity(_ measured: Double) -> Double {
    (measured < 0 ? -1 : 1) * flickSpinSpeeds.clamp(abs(measured)) * Double.random(in: 0.97...1.03)
}

private extension ClosedRange where Bound == Double {
    func clamp(_ x: Double) -> Double { Swift.min(Swift.max(x, lowerBound), upperBound) }
}
