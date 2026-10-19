import Foundation

enum Geometry {
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

    private(set) var theta: Double
    private(set) var omega = 0.0
    private(set) var root = 0.0
    private(set) var rootRate = 0.0
    private(set) var tip = 0.0
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

    init(slices: Int, theta: Double = 0, params: Params = Params()) {
        self.slices = slices
        self.segment = 2 * .pi / Double(slices)
        self.theta = theta
        self.params = params.scaled(forSlices: slices)
    }

    mutating func push(_ angularVelocity: Double) {
        omega = angularVelocity
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
            if let speed = substep() { onImpact(Impact(offset: elapsed, speed: speed, reverse: omega * direction < 0)) }
            carry -= Self.step
            elapsed += Self.step
        }
    }

    var winner: Int {
        let t = points.tip
        var a = (atan2(t.y, t.x) - theta).truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return min(Int(a / segment), slices - 1)
    }

    private var points: (joint: (x: Double, y: Double), tip: (x: Double, y: Double)) {
        let half = Geometry.segmentLength
        let joint = (x: -sin(root) * half, y: -Geometry.pivot + cos(root) * half)
        return (joint, (x: joint.x - sin(tip) * half, y: joint.y + cos(tip) * half))
    }

    private mutating func substep() -> Double? {
        let p = params
        let a = Geometry.segmentLength, b = a
        let segmentMass = p.hingeInertia / (5 * a * a)
        let rootDamping = 2 * p.hingeDampingRatio * (p.hingeStiffness * p.hingeInertia).squareRoot()
        let bendDamping = 2 * p.bendDampingRatio * (p.bendStiffness * segmentMass * b * b).squareRoot()
        let bend = p.bendStiffness * (tip - root) + bendDamping * (tipRate - rootRate)
        var forceRoot = -p.hingeStiffness * root - rootDamping * rootRate + bend
        var forceTip = -bend

        let pivot = (x: 0.0, y: -Geometry.pivot)
        let joint = points.joint
        let rootDir = (x: -sin(root), y: cos(root)), tipDir = (x: -sin(tip), y: cos(tip))
        var contactTorque = 0.0
        var impact: Double?
        var inContact = false

        let pegBeforePointer = Int(floor((-.pi / 2 - theta) / segment))
        for i in pegBeforePointer...(pegBeforePointer + 1) {
            let angle = theta + Double(i) * segment
            let cx = Geometry.pegCircle * cos(angle), cy = Geometry.pegCircle * sin(angle)

            var best: (depth: Double, q: (x: Double, y: Double), rootJacobian: (x: Double, y: Double), tipJacobian: (x: Double, y: Double))?
            for outer in [false, true] {
                let start = outer ? joint : pivot
                let dir = outer ? tipDir : rootDir
                let len = outer ? b : a
                let s = min(max((cx - start.x) * dir.x + (cy - start.y) * dir.y, 0), len)
                let q = (x: start.x + s * dir.x, y: start.y + s * dir.y)
                let depth = Geometry.pegRadius + Geometry.armRadius - ((cx - q.x) * (cx - q.x) + (cy - q.y) * (cy - q.y)).squareRoot()
                let rootJacobian = outer ? (x: -a * cos(root), y: -a * sin(root)) : (x: -s * cos(root), y: -s * sin(root))
                let tipJacobian = outer ? (x: -s * cos(tip), y: -s * sin(tip)) : (x: 0.0, y: 0.0)
                if depth > 0, depth > best?.depth ?? 0 { best = (depth, q, rootJacobian, tipJacobian) }
            }
            guard let c = best else { continue }
            inContact = true

            let sx = cx - c.q.x, sy = cy - c.q.y
            let dist = max((sx * sx + sy * sy).squareRoot(), 1e-9)
            let nx = sx / dist, ny = sy / dist
            let tx = -ny, ty = nx
            let vx = -omega * cy - (c.rootJacobian.x * rootRate + c.tipJacobian.x * tipRate)
            let vy = omega * cx - (c.rootJacobian.y * rootRate + c.tipJacobian.y * tipRate)
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
        let a = Geometry.segmentLength, b = a
        let cosD = cos(root - tip), sinD = sin(root - tip)
        let m11 = 2 * segmentMass * a * a, m12 = segmentMass * a * b * cosD, m22 = segmentMass * b * b
        let r1 = forceRoot - segmentMass * a * b * sinD * tipRate * tipRate
        let r2 = forceTip + segmentMass * a * b * sinD * rootRate * rootRate
        let det = m11 * m22 - m12 * m12
        rootRate += (r1 * m22 - m12 * r2) / det * h
        tipRate += (m11 * r2 - m12 * r1) / det * h
        root += rootRate * h
        tip += tipRate * h
    }

    private mutating func stepWheel(contactTorque: Double) {
        let p = params
        let h = Self.step
        if let fingerSpeed {
            omega = fingerSpeed
        } else {
            if stuck, abs(contactTorque) > p.staticFriction { stuck = false }
            if !stuck {
                let sliding = omega != 0 ? (omega > 0 ? 1.0 : -1.0) : (contactTorque > 0 ? 1.0 : -1.0)
                let torque = contactTorque - p.kineticFriction * sliding - p.viscousDrag * omega - p.airDrag * omega * abs(omega)
                let next = omega + torque / p.wheelInertia * h
                if next * sliding <= 0 {
                    omega = 0
                    stuck = abs(contactTorque) <= p.staticFriction
                } else {
                    omega = next
                }
            }
        }
        theta += omega * h
        time += h
        if omega * direction < -0.05 { rolledBack = true }
        peakRoot = max(peakRoot, abs(root))
        peakBend = max(peakBend, abs(tip - root))
        peakTip = max(peakTip, abs(tip))
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
