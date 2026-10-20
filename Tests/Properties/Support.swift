import Foundation
import PropertyBased
@testable import HotPotatoCore

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

func scratchDefaults() -> UserDefaults {
    UserDefaults(suiteName: "hotpotato.properties.\(UUID().uuidString)")!
}

func sliceUnderResting(flapperOver wheel: [Name], at clockwiseAngle: Double) -> Name {
    wheel[WheelSim(slices: wheel.count, clockwiseAngle: clockwiseAngle).winner]
}
