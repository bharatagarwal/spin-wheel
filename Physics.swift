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
        let joint = (x: pivot.x - sin(rootFromVertical) * segmentLength,
                     y: pivot.y + cos(rootFromVertical) * segmentLength)
        return FlapperPoints(pivot: pivot, joint: joint,
                             tip: (x: joint.x - sin(tipFromVertical) * segmentLength,
                                   y: joint.y + cos(tipFromVertical) * segmentLength))
    }

    static func sliceAngle(_ index: Int, of slices: Int) -> Double { Double(index) * 2 * .pi / Double(slices) }

    static func slicesFromFirst(to point: YDownPoint, wheelAngle: Double, slices: Int) -> Double {
        var fromFirst = (atan2(point.y, point.x) - wheelAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if fromFirst < 0 { fromFirst += 2 * .pi }
        return fromFirst / (2 * .pi / Double(slices))
    }

    static func slice(under flapper: FlapperPoints, wheelAngle: Double, slices: Int) -> Int {
        let tip = slicesFromFirst(to: flapper.tip, wheelAngle: wheelAngle, slices: slices)
        let tipRestsOnAPeg = abs(tip - tip.rounded()) * 2 * .pi / Double(slices) < pegRadius / pegCircle
        let shown = tipRestsOnAPeg
            ? slicesFromFirst(to: armOverThePegTop(flapper), wheelAngle: wheelAngle, slices: slices)
            : tip
        let slice = min(Int(shown), slices - 1)
        assert((0..<slices).contains(slice), "slice \(slice) of \(slices)")
        return slice
    }

    static func armOverThePegTop(_ flapper: FlapperPoints) -> YDownPoint {
        let back = (pegRadius + armRadius) / segmentLength
        return (x: flapper.tip.x + (flapper.joint.x - flapper.tip.x) * back,
                y: flapper.tip.y + (flapper.joint.y - flapper.tip.y) * back)
    }

    static func peg(_ index: Int, of slices: Int, wheelAngle: Double = 0) -> YDownPoint {
        let angle = wheelAngle + sliceAngle(index, of: slices)
        return (x: pegCircle * cos(angle), y: pegCircle * sin(angle))
    }
}

struct WheelPose {
    var clockwiseAngle = 0.0
    var rootFromVertical = 0.0
    var tipFromVertical = 0.0

    func clockwiseAngle(keepingSlice old: Int, of oldSlices: Int,
                        underTheFlapperAs new: Int, of newSlices: Int) -> Double {
        let tip = WheelRadii.flapper(rootFromVertical: rootFromVertical, tipFromVertical: tipFromVertical).tip
        let intoSlice = WheelRadii.slicesFromFirst(to: tip, wheelAngle: clockwiseAngle, slices: oldSlices) - Double(old)
        let target = atan2(tip.y, tip.x) - (Double(new) + intoSlice) * 2 * .pi / Double(newSlices)
        let turned = clockwiseAngle + remainder(target - clockwiseAngle, 2 * .pi)
        assert(abs(turned - clockwiseAngle) <= .pi + 1e-9, "the wheel turns the short way")
        return turned
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
        var swingLimit = 0.9
        var bendLimit = 0.5
        var contactStiffness = 3e5
        var contactDamping = 0.6
        var contactFriction = 0.15

        func scaled(forSlices slices: Int) -> Params {
            let scale = 5 / Double(max(slices, 2))
            var scaled = self
            scaled.hingeStiffness *= scale
            scaled.bendStiffness *= scale
            scaled.hingeInertia *= scale
            return scaled
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

    mutating func advance(_ frameTime: Double,
                          onImpact: (Impact) -> Void = { _ in }, onStep: (WheelSim) -> Void = { _ in }) {
        carry += frameTime
        var elapsed = 0.0
        while carry >= Self.step, !stopped {
            if let speed = substep() {
                onImpact(Impact(offset: elapsed, speed: speed, reverse: clockwiseSpeed * pushDirection < 0))
            }
            onStep(self)
            carry -= Self.step
            elapsed += Self.step
        }
    }

    var winner: Int {
        WheelRadii.slice(under: points, wheelAngle: clockwiseAngle, slices: slices)
    }

    private var points: FlapperPoints {
        WheelRadii.flapper(rootFromVertical: rootFromVertical, tipFromVertical: tipFromVertical)
    }

    private mutating func substep() -> Double? {
        let length = WheelRadii.segmentLength
        let segmentMass = params.hingeInertia / (5 * length * length)
        let rootDamping = 2 * params.hingeDampingRatio * (params.hingeStiffness * params.hingeInertia).squareRoot()
        let bendDamping = 2 * params.bendDampingRatio
            * (params.bendStiffness * segmentMass * length * length).squareRoot()
        let bend = params.bendStiffness * (tipFromVertical - rootFromVertical) + bendDamping * (tipRate - rootRate)
        let contacts = pegContacts()
        stepFlapper(forceRoot: -params.hingeStiffness * rootFromVertical - rootDamping * rootRate + bend
                        + contacts.forceRoot,
                    forceTip: -bend + contacts.forceTip, segmentMass: segmentMass)
        holdFlapperWithinStops()
        stepWheel(contactTorque: contacts.torque)
        settle()
        assert(stateIsPhysical, "\(self)")
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
        for index in pegsReachableFromPointer {
            let peg = WheelRadii.peg(index, of: slices, wheelAngle: clockwiseAngle)
            guard let contact = deepestContact(with: peg) else { continue }
            inContact = true
            addForce(of: contact, from: peg, into: &forces)
        }
        touching = inContact
        return forces
    }

    private func deepestContact(with peg: YDownPoint) -> SegmentContact? {
        let length = WheelRadii.segmentLength
        let flapper = points
        let rootDir = (x: -sin(rootFromVertical), y: cos(rootFromVertical))
        let tipDir = (x: -sin(tipFromVertical), y: cos(tipFromVertical))
        let inner = contact(with: peg, alongSegmentFrom: flapper.pivot, direction: rootDir, length: length) { along in
            ((x: -along * cos(rootFromVertical), y: -along * sin(rootFromVertical)), (x: 0.0, y: 0.0))
        }
        let outer = contact(with: peg, alongSegmentFrom: flapper.joint, direction: tipDir, length: length) { along in
            ((x: -length * cos(rootFromVertical), y: -length * sin(rootFromVertical)),
             (x: -along * cos(tipFromVertical), y: -along * sin(tipFromVertical)))
        }
        var best: SegmentContact?
        for candidate in [inner, outer] where candidate.depth > 0 && candidate.depth > best?.depth ?? 0 {
            best = candidate
        }
        return best
    }

    private func contact(with peg: YDownPoint, alongSegmentFrom start: YDownPoint,
                         direction dir: YDownPoint, length: Double,
                         jacobians: (Double) -> (root: YDownPoint, tip: YDownPoint)) -> SegmentContact {
        let along = min(max((peg.x - start.x) * dir.x + (peg.y - start.y) * dir.y, 0), length)
        let closest = (x: start.x + along * dir.x, y: start.y + along * dir.y)
        let depth = WheelRadii.pegRadius + WheelRadii.armRadius
            - ((peg.x - closest.x) * (peg.x - closest.x) + (peg.y - closest.y) * (peg.y - closest.y)).squareRoot()
        let jacobian = jacobians(along)
        return SegmentContact(depth: depth, point: closest, rootJacobian: jacobian.root, tipJacobian: jacobian.tip)
    }

    private func addForce(of contact: SegmentContact, from peg: YDownPoint, into forces: inout ContactForces) {
        let (pegX, pegY) = peg
        let offsetX = pegX - contact.point.x, offsetY = pegY - contact.point.y
        let dist = max((offsetX * offsetX + offsetY * offsetY).squareRoot(), 1e-9)
        let normalX = offsetX / dist, normalY = offsetY / dist
        let tangentX = -normalY, tangentY = normalX
        let velocityX = -clockwiseSpeed * pegY - (contact.rootJacobian.x * rootRate + contact.tipJacobian.x * tipRate)
        let velocityY = clockwiseSpeed * pegX - (contact.rootJacobian.y * rootRate + contact.tipJacobian.y * tipRate)
        let normalSpeed = velocityX * normalX + velocityY * normalY
        let tangentSpeed = velocityX * tangentX + velocityY * tangentY
        if !touching, normalSpeed < 0 { forces.impact = -normalSpeed }

        let normal = max(0, params.contactStiffness * pow(contact.depth, 1.5)
                            * (1 - 1.5 * params.contactDamping * normalSpeed))
        let friction = -params.contactFriction * normal * tanh(tangentSpeed / 0.02)
        let forceX = normal * normalX + friction * tangentX, forceY = normal * normalY + friction * tangentY
        forces.torque += pegX * forceY - pegY * forceX
        forces.forceRoot -= contact.rootJacobian.x * forceX + contact.rootJacobian.y * forceY
        forces.forceTip -= contact.tipJacobian.x * forceX + contact.tipJacobian.y * forceY
    }

    private mutating func stepFlapper(forceRoot: Double, forceTip: Double, segmentMass: Double) {
        let length = WheelRadii.segmentLength
        let cosD = cos(rootFromVertical - tipFromVertical), sinD = sin(rootFromVertical - tipFromVertical)
        let m11 = 2 * segmentMass * length * length
        let m12 = segmentMass * length * length * cosD
        let m22 = segmentMass * length * length
        let rootSide = forceRoot - segmentMass * length * length * sinD * tipRate * tipRate
        let tipSide = forceTip + segmentMass * length * length * sinD * rootRate * rootRate
        let det = m11 * m22 - m12 * m12
        rootRate += (rootSide * m22 - m12 * tipSide) / det * Self.step
        tipRate += (m11 * tipSide - m12 * rootSide) / det * Self.step
        rootFromVertical += rootRate * Self.step
        tipFromVertical += tipRate * Self.step
    }

    private mutating func stepWheel(contactTorque: Double) {
        switch phase {
        case .held(let fingerSpeed):
            clockwiseSpeed = fingerSpeed
        case .stopped:
            break
        case .stuck where abs(contactTorque) <= params.staticFriction:
            break
        case .stuck(let stillFor):
            slide(contactTorque: contactTorque, stillFor: stillFor)
        case .turning:
            slide(contactTorque: contactTorque, stillFor: 0)
        }
        clockwiseAngle += clockwiseSpeed * Self.step
        time += Self.step
    }

    private mutating func slide(contactTorque: Double, stillFor: Double) {
        let sliding = slidingDirection(contactTorque: contactTorque)
        let torque = contactTorque - params.kineticFriction * sliding - params.viscousDrag * clockwiseSpeed
            - params.airDrag * clockwiseSpeed * abs(clockwiseSpeed)
        let next = clockwiseSpeed + torque / params.wheelInertia * Self.step
        guard next * sliding > 0 else {
            clockwiseSpeed = 0
            phase = abs(contactTorque) <= params.staticFriction ? .stuck(stillFor: stillFor) : .turning
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
        if case .stuck(let stillFor) = phase {
            let flapperStill = abs(rootRate) < 0.3 && abs(tipRate) < 0.6
            let settled = flapperStill ? stillFor + Self.step : 0
            phase = settled > 0.15 ? .stopped : .stuck(stillFor: settled)
        }
        let held = if case .held = phase { true } else { false }
        if !held, time - releasedAt > 30 { phase = .stopped }
    }
}

extension WheelSim {
    fileprivate var stateIsPhysical: Bool {
        let values = [clockwiseAngle, clockwiseSpeed, rootFromVertical, rootRate, tipFromVertical, tipRate, time]
        return values.allSatisfy(\.isFinite)
            && abs(rootFromVertical) <= params.swingLimit
            && abs(tipFromVertical - rootFromVertical) <= params.bendLimit + 1e-12
    }

    fileprivate mutating func holdFlapperWithinStops() {
        if abs(rootFromVertical) > params.swingLimit {
            let outward = rootFromVertical < 0 ? -1.0 : 1.0
            rootFromVertical = outward * params.swingLimit
            if rootRate * outward > 0 { rootRate = 0 }
        }
        let bend = tipFromVertical - rootFromVertical
        if abs(bend) > params.bendLimit {
            let outward = bend < 0 ? -1.0 : 1.0
            tipFromVertical = rootFromVertical + outward * params.bendLimit
            if (tipRate - rootRate) * outward > 0 { tipRate = rootRate }
        }
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
        let radiusDraw = Double.random(in: Double.ulpOfOne..<1, using: &rng)
        let angleDraw = Double.random(in: 0..<1, using: &rng)
        let deviations = (-2 * log(radiusDraw)).squareRoot() * cos(2 * .pi * angleDraw)
        if abs(deviations) <= pushSpeedMaxDeviations { return mean + pushSpeedStandardDeviation * deviations }
    }
}

private extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
