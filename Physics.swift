import Foundation

/// Wheel geometry in units of the wheel face radius, in screen coordinates
/// (origin at the hub, y pointing down, positive angles clockwise).
/// The view draws from these same numbers, so what you see is what collides.
enum Geometry {
    static let pegCircle = 0.93      // distance of peg centres from the hub
    static let pegRadius = 0.016
    static let pivot = 1.06          // flapper hinge, mounted on the rim above the hub
    static let armLength = 0.16
    static let armRadius = 0.010     // half-thickness of the flapper near its tip
}

/// Two rigid bodies: a wheel on a bearing and a spring-hinged flapper,
/// coupled only through peg contacts. Nothing chooses the result; the wheel
/// stops wherever it runs out of energy.
struct WheelSim {
    struct Params {
        var wheelInertia = 1.0
        var bearingFriction = 1.8       // Coulomb torque, gives a finite stop
        var viscousDrag = 0.05
        var airDrag = 0.004             // grows with speed squared
        var flapperInertia = 0.0007
        var flapperStiffness = 4.0      // torsional spring, torque per radian
        var flapperDampingRatio = 0.12
        var contactStiffness = 3e5      // Hertzian: force = k * depth^1.5
        var contactDamping = 0.15       // Hunt–Crossley, sets how dead the knock is
        var contactFriction = 0.15
    }

    let slices: Int
    let segment: Double
    var params: Params

    private(set) var theta: Double      // wheel angle
    private(set) var omega = 0.0
    private(set) var phi = 0.0          // flapper angle, 0 = hanging straight down
    private(set) var phiDot = 0.0
    private(set) var time = 0.0
    private(set) var stopped = false
    private(set) var rolledBack = false

    static let step = 1.0 / 8000
    private var carry = 0.0
    private var touching = false
    private var still = 0.0

    init(slices: Int, theta: Double = 0, params: Params = Params()) {
        self.slices = slices
        self.segment = 2 * .pi / Double(slices)
        self.theta = theta
        self.params = params
        // Keep the energy taken per revolution roughly constant whatever the team size.
        self.params.flapperStiffness *= 5 / Double(max(slices, 2))
    }

    mutating func push(_ angularVelocity: Double) {
        omega = angularVelocity
        stopped = false
    }

    /// Advance by `dt` of real time. `onImpact(offset, speed, reverse)` fires for each
    /// peg strike, with its offset into this interval so sound can be placed precisely.
    mutating func advance(_ dt: Double, onImpact: (Double, Double, Bool) -> Void = { _, _, _ in }) {
        carry += dt
        var elapsed = 0.0
        while carry >= Self.step, !stopped {
            if let speed = substep() { onImpact(elapsed, speed, omega < 0) }
            carry -= Self.step
            elapsed += Self.step
        }
    }

    /// Slice under the flapper tip, which is where a real wheel is read.
    var winner: Int {
        let tip = tipPosition
        var a = (atan2(tip.y, tip.x) - theta).truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return min(Int(a / segment), slices - 1)
    }

    private var tipPosition: (x: Double, y: Double) {
        (-sin(phi) * Geometry.armLength, -Geometry.pivot + cos(phi) * Geometry.armLength)
    }

    private mutating func substep() -> Double? {
        let p = params
        let h = Self.step
        var wheelTorque = -p.bearingFriction * tanh(omega / 0.05) - p.viscousDrag * omega - p.airDrag * omega * abs(omega)
        let flapperDamping = 2 * p.flapperDampingRatio * (p.flapperStiffness * p.flapperInertia).squareRoot()
        var flapperTorque = -p.flapperStiffness * phi - flapperDamping * phiDot

        let px = 0.0, py = -Geometry.pivot
        let dx = -sin(phi), dy = cos(phi)
        var impact: Double?
        var inContact = false

        // Only the two pegs either side of the pointer can reach the flapper.
        let nearest = Int(floor((-.pi / 2 - theta) / segment))
        for i in nearest...(nearest + 1) {
            let a = theta + Double(i) * segment
            let cx = Geometry.pegCircle * cos(a), cy = Geometry.pegCircle * sin(a)
            let u = min(max(((cx - px) * dx + (cy - py) * dy) / Geometry.armLength, 0), 1)
            let qx = px + u * Geometry.armLength * dx, qy = py + u * Geometry.armLength * dy
            let sx = cx - qx, sy = cy - qy
            let dist = (sx * sx + sy * sy).squareRoot()
            let depth = Geometry.pegRadius + Geometry.armRadius - dist
            guard depth > 0, dist > 1e-9 else { continue }
            inContact = true

            let nx = sx / dist, ny = sy / dist
            let tx = -ny, ty = nx
            let vx = -omega * cy + phiDot * (qy - py)
            let vy = omega * cx - phiDot * (qx - px)
            let vn = vx * nx + vy * ny
            let vt = vx * tx + vy * ty
            if !touching, vn < 0 { impact = -vn }

            let normal = max(0, p.contactStiffness * pow(depth, 1.5) * (1 - 1.5 * p.contactDamping * vn))
            let friction = -p.contactFriction * normal * tanh(vt / 0.02)
            let fx = normal * nx + friction * tx, fy = normal * ny + friction * ty
            wheelTorque += cx * fy - cy * fx
            flapperTorque -= (qx - px) * fy - (qy - py) * fx
        }
        touching = inContact

        omega += wheelTorque / p.wheelInertia * h
        phiDot += flapperTorque / p.flapperInertia * h
        theta += omega * h
        phi += phiDot * h
        time += h
        if omega < -0.05 { rolledBack = true }

        if abs(omega) < 0.02, abs(phiDot) < 0.3, !inContact {
            still += h
            if still > 0.25 { stopped = true; omega = 0 }
        } else {
            still = 0
        }
        if time > 30 { stopped = true }
        return impact
    }
}

/// Strength of a button-press spin, in radians per second.
func spinVelocity() -> Double { Double.random(in: 12...15) }
