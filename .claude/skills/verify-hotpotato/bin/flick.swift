import CoreGraphics
import Foundation

let numbers = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard numbers.count == 5 else { print("usage: flick <cx> <cy> <radius> <degrees> <seconds>"); exit(1) }
let (centerX, centerY, radius) = (numbers[0], numbers[1], numbers[2])
let (sweep, seconds) = (numbers[3] * .pi / 180, numbers[4])

func pointer(at progress: Double) -> CGPoint {
    let angle = -Double.pi / 2 + sweep * progress
    return CGPoint(x: centerX + radius * cos(angle), y: centerY + radius * sin(angle))
}

func post(_ type: CGEventType, _ position: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

post(.mouseMoved, pointer(at: 0)); usleep(80_000)
post(.leftMouseDown, pointer(at: 0)); usleep(40_000)
let steps = 30
for step in 1...steps {
    post(.leftMouseDragged, pointer(at: Double(step) / Double(steps)))
    usleep(useconds_t(seconds / Double(steps) * 1e6))
}
post(.leftMouseUp, pointer(at: 1))
