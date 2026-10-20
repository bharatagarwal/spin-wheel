import Foundation

typealias YDownPoint = (x: Double, y: Double)

struct FlapperPoints {
    let pivot: YDownPoint
    let joint: YDownPoint
    let tip: YDownPoint
}

enum WheelRadii {
    static let pegCircle = 0.93
    static let pegRadius = 0.016
    static let pivot = 1.06
    static let armLength = 0.115
    static let segmentLength = armLength / 2
    static let armRadius = 0.010
    static let flapperReach = armLength + armRadius + pegRadius
    static let pegAngleReachableFromPointer = asin(min(1, flapperReach / pegCircle))

    static func flapper(rootFromVertical: Double, tipFromVertical: Double) -> FlapperPoints {
        let pivot = (x: 0.0, y: -WheelRadii.pivot)
        let joint = (x: pivot.x - sin(rootFromVertical) * segmentLength, y: pivot.y + cos(rootFromVertical) * segmentLength)
        return FlapperPoints(pivot: pivot, joint: joint,
                             tip: (x: joint.x - sin(tipFromVertical) * segmentLength, y: joint.y + cos(tipFromVertical) * segmentLength))
    }

    static func sliceAngle(_ i: Int, of slices: Int) -> Double { Double(i) * 2 * .pi / Double(slices) }

    static func slicesFromFirst(to point: YDownPoint, wheelAngle: Double, slices: Int) -> Double {
        var a = (atan2(point.y, point.x) - wheelAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return a / (2 * .pi / Double(slices))
    }

    static func peg(_ i: Int, of slices: Int, wheelAngle: Double = 0) -> YDownPoint {
        let angle = wheelAngle + sliceAngle(i, of: slices)
        return (x: pegCircle * cos(angle), y: pegCircle * sin(angle))
    }
}

struct WheelPose {
    var clockwiseAngle = 0.0
    var rootFromVertical = 0.0
    var tipFromVertical = 0.0

    func clockwiseAngle(keepingSlice old: Int, of oldSlices: Int, underTheFlapperAs new: Int, of newSlices: Int) -> Double {
        let tip = WheelRadii.flapper(rootFromVertical: rootFromVertical, tipFromVertical: tipFromVertical).tip
        let intoSlice = WheelRadii.slicesFromFirst(to: tip, wheelAngle: clockwiseAngle, slices: oldSlices) - Double(old)
        let target = atan2(tip.y, tip.x) - (Double(new) + intoSlice) * 2 * .pi / Double(newSlices)
        return clockwiseAngle + remainder(target - clockwiseAngle, 2 * .pi)
    }
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

    enum Phase {
        case held(clockwiseSpeed: Double)
        case turning
        case stuck(stillFor: Double)
        case stopped
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
    private(set) var pushDirection = 1.0
    private(set) var phase = Phase.stuck(stillFor: 0)

    static let step = 1.0 / 8000
    private var carry = 0.0
    private var releasedAt = 0.0
    private var touching = false

    init(slices: Int, clockwiseAngle: Double = 0, params: Params = Params()) {
        self.slices = slices
        self.segment = 2 * .pi / Double(slices)
        self.clockwiseAngle = clockwiseAngle
        self.params = params.scaled(forSlices: slices)
    }

    mutating func push(_ angularVelocity: Double) {
        clockwiseSpeed = angularVelocity
        pushDirection = angularVelocity < 0 ? -1 : 1
        phase = .turning
        releasedAt = time
    }

    mutating func drive(_ angularVelocity: Double) {
        phase = .held(clockwiseSpeed: angularVelocity)
    }

    var stopped: Bool {
        if case .stopped = phase { true } else { false }
    }

    mutating func advance(_ dt: Double, onImpact: (Impact) -> Void = { _ in }, onStep: (WheelSim) -> Void = { _ in }) {
        carry += dt
        var elapsed = 0.0
        while carry >= Self.step, !stopped {
            if let speed = substep() { onImpact(Impact(offset: elapsed, speed: speed, reverse: clockwiseSpeed * pushDirection < 0)) }
            onStep(self)
            carry -= Self.step
            elapsed += Self.step
        }
    }

    var winner: Int {
        min(Int(WheelRadii.slicesFromFirst(to: points.tip, wheelAngle: clockwiseAngle, slices: slices)), slices - 1)
    }

    private var points: FlapperPoints {
        WheelRadii.flapper(rootFromVertical: rootFromVertical, tipFromVertical: tipFromVertical)
    }

    private mutating func substep() -> Double? {
        let p = params
        let a = WheelRadii.segmentLength, b = a
        let segmentMass = p.hingeInertia / (5 * a * a)
        let rootDamping = 2 * p.hingeDampingRatio * (p.hingeStiffness * p.hingeInertia).squareRoot()
        let bendDamping = 2 * p.bendDampingRatio * (p.bendStiffness * segmentMass * b * b).squareRoot()
        let bend = p.bendStiffness * (tipFromVertical - rootFromVertical) + bendDamping * (tipRate - rootRate)
        let contacts = pegContacts()
        stepFlapper(forceRoot: -p.hingeStiffness * rootFromVertical - rootDamping * rootRate + bend + contacts.forceRoot,
                    forceTip: -bend + contacts.forceTip, segmentMass: segmentMass)
        stepWheel(contactTorque: contacts.torque)
        settle()
        return contacts.impact
    }

    private var pegsReachableFromPointer: Range<Int> {
        let pointer = -Double.pi / 2 - clockwiseAngle
        let first = Int(ceil((pointer - WheelRadii.pegAngleReachableFromPointer) / segment))
        let last = Int(floor((pointer + WheelRadii.pegAngleReachableFromPointer) / segment))
        return first..<max(first, last + 1)
    }

    private struct SegmentContact {
        let depth: Double
        let point: YDownPoint
        let rootJacobian: YDownPoint
        let tipJacobian: YDownPoint
    }

    private struct ContactForces {
        var forceRoot = 0.0
        var forceTip = 0.0
        var torque = 0.0
        var impact: Double?
    }

    private mutating func pegContacts() -> ContactForces {
        var forces = ContactForces()
        var inContact = false
        for i in pegsReachableFromPointer {
            let peg = WheelRadii.peg(i, of: slices, wheelAngle: clockwiseAngle)
            guard let contact = deepestContact(with: peg) else { continue }
            inContact = true
            addForce(of: contact, from: peg, into: &forces)
        }
        touching = inContact
        return forces
    }

    private func deepestContact(with peg: YDownPoint) -> SegmentContact? {
        let a = WheelRadii.segmentLength, b = a
        let flapper = points
        let rootDir = (x: -sin(rootFromVertical), y: cos(rootFromVertical)), tipDir = (x: -sin(tipFromVertical), y: cos(tipFromVertical))
        let inner = contact(with: peg, alongSegmentFrom: flapper.pivot, direction: rootDir, length: a) { s in
            ((x: -s * cos(rootFromVertical), y: -s * sin(rootFromVertical)), (x: 0.0, y: 0.0))
        }
        let outer = contact(with: peg, alongSegmentFrom: flapper.joint, direction: tipDir, length: b) { s in
            ((x: -a * cos(rootFromVertical), y: -a * sin(rootFromVertical)), (x: -s * cos(tipFromVertical), y: -s * sin(tipFromVertical)))
        }
        var best: SegmentContact?
        for candidate in [inner, outer] where candidate.depth > 0 && candidate.depth > best?.depth ?? 0 {
            best = candidate
        }
        return best
    }

    private func contact(with peg: YDownPoint, alongSegmentFrom start: YDownPoint, direction dir: YDownPoint, length: Double,
                         jacobians: (Double) -> (root: YDownPoint, tip: YDownPoint)) -> SegmentContact {
        let s = min(max((peg.x - start.x) * dir.x + (peg.y - start.y) * dir.y, 0), length)
        let q = (x: start.x + s * dir.x, y: start.y + s * dir.y)
        let depth = WheelRadii.pegRadius + WheelRadii.armRadius - ((peg.x - q.x) * (peg.x - q.x) + (peg.y - q.y) * (peg.y - q.y)).squareRoot()
        let j = jacobians(s)
        return SegmentContact(depth: depth, point: q, rootJacobian: j.root, tipJacobian: j.tip)
    }

    private func addForce(of c: SegmentContact, from peg: YDownPoint, into forces: inout ContactForces) {
        let p = params
        let (cx, cy) = peg
        let sx = cx - c.point.x, sy = cy - c.point.y
        let dist = max((sx * sx + sy * sy).squareRoot(), 1e-9)
        let nx = sx / dist, ny = sy / dist
        let tx = -ny, ty = nx
        let vx = -clockwiseSpeed * cy - (c.rootJacobian.x * rootRate + c.tipJacobian.x * tipRate)
        let vy = clockwiseSpeed * cx - (c.rootJacobian.y * rootRate + c.tipJacobian.y * tipRate)
        let vn = vx * nx + vy * ny
        let vt = vx * tx + vy * ty
        if !touching, vn < 0 { forces.impact = -vn }

        let normal = max(0, p.contactStiffness * pow(c.depth, 1.5) * (1 - 1.5 * p.contactDamping * vn))
        let friction = -p.contactFriction * normal * tanh(vt / 0.02)
        let fx = normal * nx + friction * tx, fy = normal * ny + friction * ty
        forces.torque += cx * fy - cy * fx
        forces.forceRoot -= c.rootJacobian.x * fx + c.rootJacobian.y * fy
        forces.forceTip -= c.tipJacobian.x * fx + c.tipJacobian.y * fy
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
        switch phase {
        case .held(let fingerSpeed):
            clockwiseSpeed = fingerSpeed
        case .stopped:
            break
        case .stuck where abs(contactTorque) <= p.staticFriction:
            break
        case .stuck(let stillFor):
            slide(contactTorque: contactTorque, stillFor: stillFor)
        case .turning:
            slide(contactTorque: contactTorque, stillFor: 0)
        }
        clockwiseAngle += clockwiseSpeed * h
        time += h
    }

    private mutating func slide(contactTorque: Double, stillFor: Double) {
        let p = params
        let sliding = slidingDirection(contactTorque: contactTorque)
        let torque = contactTorque - p.kineticFriction * sliding - p.viscousDrag * clockwiseSpeed - p.airDrag * clockwiseSpeed * abs(clockwiseSpeed)
        let next = clockwiseSpeed + torque / p.wheelInertia * Self.step
        guard next * sliding > 0 else {
            clockwiseSpeed = 0
            phase = abs(contactTorque) <= p.staticFriction ? .stuck(stillFor: stillFor) : .turning
            return
        }
        clockwiseSpeed = next
        phase = .turning
    }

    private func slidingDirection(contactTorque: Double) -> Double {
        if clockwiseSpeed > 0 { return 1 }
        if clockwiseSpeed < 0 { return -1 }
        return contactTorque > 0 ? 1 : -1
    }

    private mutating func settle() {
        let h = Self.step
        if case .stuck(let stillFor) = phase {
            let flapperStill = abs(rootRate) < 0.3 && abs(tipRate) < 0.6
            let settled = flapperStill ? stillFor + h : 0
            phase = settled > 0.15 ? .stopped : .stuck(stillFor: settled)
        }
        let held = if case .held = phase { true } else { false }
        if !held, time - releasedAt > 30 { phase = .stopped }
    }
}

let buttonPushMeanSpeed = 10.0
let flickPushMeanSpeeds = 8.0...12.0
let pushSpeedStandardDeviation = 2.0
let pushSpeedMaxDeviations = 2.5

func spinVelocity(using rng: inout some RandomNumberGenerator) -> Double {
    normallyVariedPush(around: buttonPushMeanSpeed, using: &rng)
}

func flickVelocity(_ measured: Double, using rng: inout some RandomNumberGenerator) -> Double {
    (measured < 0 ? -1 : 1) * normallyVariedPush(around: flickPushMeanSpeeds.clamp(abs(measured)), using: &rng)
}

private func normallyVariedPush(around mean: Double, using rng: inout some RandomNumberGenerator) -> Double {
    while true {
        let u = Double.random(in: Double.ulpOfOne..<1, using: &rng), v = Double.random(in: 0..<1, using: &rng)
        let deviations = (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        if abs(deviations) <= pushSpeedMaxDeviations { return mean + pushSpeedStandardDeviation * deviations }
    }
}

private extension ClosedRange where Bound == Double {
    func clamp(_ x: Double) -> Double { Swift.min(Swift.max(x, lowerBound), upperBound) }
}
