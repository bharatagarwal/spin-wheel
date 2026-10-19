import AppKit
import ApplicationServices

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }

func walk(_ e: AXUIElement, depth: Int = 0, _ visit: (AXUIElement, Int) -> Bool) -> Bool {
    if visit(e, depth) { return true }
    for c in children(e) where walk(c, depth: depth + 1, visit) { return true }
    return false
}

func find(_ app: AXUIElement, _ id: String) -> AXUIElement? {
    var hit: AXUIElement?
    _ = walk(app) { e, _ in
        if attr(e, "AXIdentifier") as? String == id { hit = e; return true }
        return false
    }
    return hit
}

func describe(_ e: AXUIElement) -> String {
    // SwiftUI puts .accessibilityValue on non-control elements in AXValueDescription.
    for name in [kAXValueAttribute, "AXValueDescription", kAXTitleAttribute] {
        if let v = attr(e, name).map({ "\($0)" }), !v.isEmpty { return v }
    }
    return ""
}

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]) else { fail("usage: ax <pid> tree|press|get|set|wait|window-id ...") }
guard AXIsProcessTrusted() else { fail("accessibility permission missing for this terminal (System Settings > Privacy & Security > Accessibility)") }
let app = AXUIElementCreateApplication(pid)

switch args[2] {
case "tree":
    // Windows only: the menu bar carries the user's system-wide Recent Items.
    for window in attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
    _ = walk(window) { e, depth in
        let role = attr(e, kAXRoleAttribute) as? String ?? "?"
        let id = attr(e, "AXIdentifier") as? String ?? ""
        let enabled = (attr(e, kAXEnabledAttribute) as? Bool).map { $0 ? "" : " [disabled]" } ?? ""
        print(String(repeating: "  ", count: depth) + role + (id.isEmpty ? "" : " #\(id)") + " \"\(describe(e))\"" + enabled)
        return false
    }
    }
case "press":
    guard args.count == 4, let e = find(app, args[3]) else { fail("no element #\(args.count > 3 ? args[3] : "")") }
    if (attr(e, kAXEnabledAttribute) as? Bool) == false { fail("#\(args[3]) is disabled") }
    guard AXUIElementPerformAction(e, kAXPressAction as CFString) == .success else { fail("press #\(args[3]) failed") }
case "get":
    guard args.count == 4, let e = find(app, args[3]) else { fail("no element #\(args.count > 3 ? args[3] : "")") }
    print(describe(e))
case "set":
    guard args.count == 5, let e = find(app, args[3]) else { fail("usage: ax <pid> set <id> <text>") }
    AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    guard AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, args[4] as CFString) == .success else { fail("set #\(args[3]) failed") }
case "wait":
    guard args.count >= 5 else { fail("usage: ax <pid> wait <id> <value> [seconds]") }
    let deadline = Date().addingTimeInterval(Double(args.count > 5 ? args[5] : "30") ?? 30)
    while Date() < deadline {
        if let e = find(app, args[3]), describe(e) == args[4] { exit(0) }
        usleep(50_000)
    }
    fail("timed out waiting for #\(args[3]) == \"\(args[4])\"")
case "frame":
    guard args.count == 4, let e = find(app, args[3]), let pos = attr(e, kAXPositionAttribute), let size = attr(e, kAXSizeAttribute) else { fail("no frame for #\(args.count > 3 ? args[3] : "")") }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    print(Int(p.x), Int(p.y), Int(s.width), Int(s.height))
case "window-id":
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let w = list.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }),
          let n = w[kCGWindowNumber as String] else { fail("no on-screen window for pid \(pid)") }
    print(n)
default:
    fail("unknown command \(args[2])")
}
