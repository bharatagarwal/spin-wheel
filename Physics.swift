import Foundation

/// Wheel geometry in units of the wheel face radius, in screen coordinates
/// (origin at the hub, y pointing down, positive angles clockwise).
/// The view draws from these same numbers, so what you see is what collides.
enum Geometry {
    static let pegCircle = 0.93      // distance of peg centres from the hub
    static let pegRadius = 0.016
    static let pivot = 1.06          // flapper hinge, mounted on the rim above the hub
    static let armLength = 0.115     // hinge to tip; the flapper bends at its midpoint
    static let armRadius = 0.010     // half-thickness of the flapper near its tip
}

/// A wheel on a bearing and a flexible two-segment flapper, coupled only
/// through peg contacts. Nothing chooses the result; the wheel stops wherever
/// it runs out of energy.
struct WheelSim {
    struct Params {
        var wheelInertia = 1.0
        var bearingFriction = 1.3       // kinetic Coulomb torque
        var staticFriction = 1.8        // torque needed to unstick a wheel at rest
        var viscousDrag = 0.013
        var airDrag = 0.00065           // grows with speed squared
        var flapperInertia = 0.0007     // whole flapper about its hinge
        var flapperStiffness = 5.0      // hinge spring, torque per radian
        var flapperDampingRatio = 0.45
        var bendStiffness = 12.0        // spring at the flapper's midpoint
        var bendDampingRatio = 0.15     // low, so the tip whips and rings
        var contactStiffness = 3e5      // Hertzian: force = k * depth^1.5
        var contactDamping = 0.6        // Hunt–Crossley, sets how dead the knock is
        var contactFriction = 0.15
    }

    let slices: Int
    let segment: Double
    var params: Params

    private(set) var theta: Double      // wheel angle
    private(set) var omega = 0.0
    private(set) var root = 0.0         // inner flapper segment, 0 = hanging straight down
    private(set) var rootRate = 0.0
    private(set) var tip = 0.0          // outer segment, absolute angle
    private(set) var tipRate = 0.0
    private(set) var time = 0.0
    private(set) var stopped = false
    private(set) var rolledBack = false
    private(set) var peakSwing = 0.0    // largest |root| seen, radians
    private(set) var peakBend = 0.0     // largest |tip - root| seen, radians
    private(set) var peakTip = 0.0      // largest |tip| seen: how far the visible end swings

    static let step = 1.0 / 8000
    private var carry = 0.0
    private var touching = false
    private var still = 0.0
    private var stuck = true            // bearing in static friction
    private var driven: Double?         // wheel speed imposed by a dragging finger
    private var direction = 1.0

    init(slices: Int, theta: Double = 0, params: Params = Params()) {
        self.slices = slices
        self.segment = 2 * .pi / Double(slices)
        self.theta = theta
        self.params = params
        // Keep the energy taken per revolution constant whatever the team size. Scaling
        // springs and mass together keeps the flapper's frequencies, so it looks the same.
        let scale = 5 / Double(max(slices, 2))
        self.params.flapperStiffness *= scale
        self.params.bendStiffness *= scale
        self.params.flapperInertia *= scale
    }

    /// Let go of the wheel at this speed (radians per second, positive is clockwise).
    mutating func push(_ angularVelocity: Double) {
        omega = angularVelocity
        direction = angularVelocity < 0 ? -1 : 1
        driven = nil
        stuck = false
        stopped = false
    }

    /// Hold the wheel at this speed, as a finger dragging it does. The flapper still reacts.
    mutating func drive(_ angularVelocity: Double) {
        driven = angularVelocity
        stuck = false
        stopped = false
    }

    /// Advance by `dt` of real time. `onImpact(offset, speed, reverse)` fires for each
    /// peg strike, with its offset into this interval so sound can be placed precisely.
    mutating func advance(_ dt: Double, onImpact: (Double, Double, Bool) -> Void = { _, _, _ in }) {
        carry += dt
        var elapsed = 0.0
        while carry >= Self.step, !stopped {
            if let speed = substep() { onImpact(elapsed, speed, omega * direction < 0) }
            carry -= Self.step
            elapsed += Self.step
        }
    }

    /// Slice under the flapper tip, which is where a real wheel is read.
    var winner: Int {
        let t = points.tip
        var a = (atan2(t.y, t.x) - theta).truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return min(Int(a / segment), slices - 1)
    }

    private var points: (joint: (x: Double, y: Double), tip: (x: Double, y: Double)) {
        let half = Geometry.armLength / 2
        let joint = (x: -sin(root) * half, y: -Geometry.pivot + cos(root) * half)
        return (joint, (x: joint.x - sin(tip) * half, y: joint.y + cos(tip) * half))
    }

    private mutating func substep() -> Double? {
        let p = params
        let h = Self.step
        let a = Geometry.armLength / 2, b = a
        // Two equal point masses, at the joint and the tip, sized to the flapper's inertia.
        let m = p.flapperInertia / (5 * a * a)
        let rootDamping = 2 * p.flapperDampingRatio * (p.flapperStiffness * p.flapperInertia).squareRoot()
        let bendDamping = 2 * p.bendDampingRatio * (p.bendStiffness * m * b * b).squareRoot()
        let bend = p.bendStiffness * (tip - root) + bendDamping * (tipRate - rootRate)
        var forceRoot = -p.flapperStiffness * root - rootDamping * rootRate + bend
        var forceTip = -bend

        let pivot = (x: 0.0, y: -Geometry.pivot)
        let joint = points.joint
        let rootDir = (x: -sin(root), y: cos(root)), tipDir = (x: -sin(tip), y: cos(tip))
        var contactTorque = 0.0
        var impact: Double?
        var inContact = false

        // Only the two pegs either side of the pointer can reach the flapper.
        let nearest = Int(floor((-.pi / 2 - theta) / segment))
        for i in nearest...(nearest + 1) {
            let angle = theta + Double(i) * segment
            let cx = Geometry.pegCircle * cos(angle), cy = Geometry.pegCircle * sin(angle)

            // Closest point on either segment; a peg at the joint touches only the nearer one.
            var best: (depth: Double, q: (x: Double, y: Double), j1: (x: Double, y: Double), j2: (x: Double, y: Double))?
            for outer in [false, true] {
                let start = outer ? joint : pivot
                let dir = outer ? tipDir : rootDir
                let len = outer ? b : a
                let s = min(max((cx - start.x) * dir.x + (cy - start.y) * dir.y, 0), len)
                let q = (x: start.x + s * dir.x, y: start.y + s * dir.y)
                let depth = Geometry.pegRadius + Geometry.armRadius - ((cx - q.x) * (cx - q.x) + (cy - q.y) * (cy - q.y)).squareRoot()
                // How the contact point moves per radian of each segment.
                let j1 = outer ? (x: -a * cos(root), y: -a * sin(root)) : (x: -s * cos(root), y: -s * sin(root))
                let j2 = outer ? (x: -s * cos(tip), y: -s * sin(tip)) : (x: 0.0, y: 0.0)
                if depth > 0, depth > best?.depth ?? 0 { best = (depth, q, j1, j2) }
            }
            guard let c = best else { continue }
            inContact = true

            let sx = cx - c.q.x, sy = cy - c.q.y
            let dist = max((sx * sx + sy * sy).squareRoot(), 1e-9)
            let nx = sx / dist, ny = sy / dist
            let tx = -ny, ty = nx
            let vx = -omega * cy - (c.j1.x * rootRate + c.j2.x * tipRate)
            let vy = omega * cx - (c.j1.y * rootRate + c.j2.y * tipRate)
            let vn = vx * nx + vy * ny
            let vt = vx * tx + vy * ty
            if !touching, vn < 0 { impact = -vn }

            let normal = max(0, p.contactStiffness * pow(c.depth, 1.5) * (1 - 1.5 * p.contactDamping * vn))
            let friction = -p.contactFriction * normal * tanh(vt / 0.02)
            let fx = normal * nx + friction * tx, fy = normal * ny + friction * ty
            contactTorque += cx * fy - cy * fx
            forceRoot -= c.j1.x * fx + c.j1.y * fy
            forceTip -= c.j2.x * fx + c.j2.y * fy
        }
        touching = inContact

        // Flapper: a double pendulum with springs at the hinge and the midpoint.
        let cosD = cos(root - tip), sinD = sin(root - tip)
        let m11 = 2 * m * a * a, m12 = m * a * b * cosD, m22 = m * b * b
        let r1 = forceRoot - m * a * b * sinD * tipRate * tipRate
        let r2 = forceTip + m * a * b * sinD * rootRate * rootRate
        let det = m11 * m22 - m12 * m12
        rootRate += (r1 * m22 - m12 * r2) / det * h
        tipRate += (m11 * r2 - m12 * r1) / det * h
        root += rootRate * h
        tip += tipRate * h

        // Wheel: Coulomb bearing that sticks at rest until the static limit is exceeded.
        if let driven {
            omega = driven
        } else {
            if stuck, abs(contactTorque) > p.staticFriction { stuck = false }
            if !stuck {
                let sliding = omega != 0 ? (omega > 0 ? 1.0 : -1.0) : (contactTorque > 0 ? 1.0 : -1.0)
                let torque = contactTorque - p.bearingFriction * sliding - p.viscousDrag * omega - p.airDrag * omega * abs(omega)
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
        peakSwing = max(peakSwing, abs(root))
        peakBend = max(peakBend, abs(tip - root))
        peakTip = max(peakTip, abs(tip))

        // Done once the bearing has locked and the flapper has stopped moving.
        if driven == nil, stuck, abs(rootRate) < 0.3, abs(tipRate) < 0.6 {
            still += h
            if still > 0.15 { stopped = true }
        } else {
            still = 0
        }
        if time > 30 { stopped = true }
        return impact
    }
}

/// Strength of a button-press spin, in radians per second.
func spinVelocity() -> Double { Double.random(in: 9...11) }

/// Release speed for a flick. Direction is the user's; strength is kept to the
/// button's range so a gentle drag can't place the wheel on a chosen slice.
func flickVelocity(_ measured: Double) -> Double {
    (measured < 0 ? -1 : 1) * min(max(abs(measured), 9), 12) * Double.random(in: 0.97...1.03)
}
