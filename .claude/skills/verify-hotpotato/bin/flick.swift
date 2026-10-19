import CoreGraphics
import Foundation

let a = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard a.count == 5 else { print("usage: flick <cx> <cy> <radius> <degrees> <seconds>"); exit(1) }
let (cx, cy, r, sweep, secs) = (a[0], a[1], a[2], a[3] * .pi / 180, a[4])
func at(_ t: Double) -> CGPoint { let ang = -Double.pi / 2 + sweep * t; return CGPoint(x: cx + r * cos(ang), y: cy + r * sin(ang)) }
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
post(.mouseMoved, at(0)); usleep(80_000)
post(.leftMouseDown, at(0)); usleep(40_000)
let steps = 30
for i in 1...steps { post(.leftMouseDragged, at(Double(i) / Double(steps))); usleep(useconds_t(secs / Double(steps) * 1e6)) }
post(.leftMouseUp, at(1))
