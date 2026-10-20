import AppKit
import ApplicationServices

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func walk(_ element: AXUIElement, depth: Int = 0, _ visit: (AXUIElement, Int) -> Bool) -> Bool {
    if visit(element, depth) { return true }
    for child in children(element) where walk(child, depth: depth + 1, visit) { return true }
    return false
}

func find(_ app: AXUIElement, _ id: String) -> AXUIElement? {
    var hit: AXUIElement?
    _ = walk(app) { element, _ in
        if attr(element, "AXIdentifier") as? String == id { hit = element; return true }
        return false
    }
    return hit
}

func describe(_ element: AXUIElement) -> String {
    // SwiftUI puts .accessibilityValue on non-control elements in AXValueDescription.
    for name in [kAXValueAttribute, "AXValueDescription", kAXTitleAttribute] {
        if let value = attr(element, name).map({ "\($0)" }), !value.isEmpty { return value }
    }
    return ""
}

func axValue(_ object: AnyObject, of id: String) -> AXValue {
    guard CFGetTypeID(object) == AXValueGetTypeID() else { fail("#\(id) has no frame") }
    return unsafeDowncast(object, to: AXValue.self)
}

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]) else { fail("usage: ax <pid> tree|press|get|set|wait|window-id ...") }
guard AXIsProcessTrusted() else {
    fail("accessibility permission missing for this terminal (System Settings > Privacy & Security > Accessibility)")
}
let app = AXUIElementCreateApplication(pid)

switch args[2] {
case "tree":
    // Windows only: the menu bar carries the user's system-wide Recent Items.
    for window in attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
    _ = walk(window) { element, depth in
        let role = attr(element, kAXRoleAttribute) as? String ?? "?"
        let id = attr(element, "AXIdentifier") as? String ?? ""
        let enabled = (attr(element, kAXEnabledAttribute) as? Bool).map { $0 ? "" : " [disabled]" } ?? ""
        let label = role + (id.isEmpty ? "" : " #\(id)") + " \"\(describe(element))\"" + enabled
        print(String(repeating: "  ", count: depth) + label)
        return false
    }
    }
case "press":
    guard args.count == 4, let element = find(app, args[3]) else {
        fail("no element #\(args.count > 3 ? args[3] : "")")
    }
    if (attr(element, kAXEnabledAttribute) as? Bool) == false { fail("#\(args[3]) is disabled") }
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        fail("press #\(args[3]) failed")
    }
case "get":
    guard args.count == 4, let element = find(app, args[3]) else {
        fail("no element #\(args.count > 3 ? args[3] : "")")
    }
    print(describe(element))
case "set":
    guard args.count == 5, let element = find(app, args[3]) else { fail("usage: ax <pid> set <id> <text>") }
    AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, args[4] as CFString) == .success else {
        fail("set #\(args[3]) failed")
    }
case "wait":
    guard args.count >= 5 else { fail("usage: ax <pid> wait <id> <value> [seconds]") }
    let deadline = Date().addingTimeInterval(Double(args.count > 5 ? args[5] : "30") ?? 30)
    while Date() < deadline {
        if let element = find(app, args[3]), describe(element) == args[4] { exit(0) }
        usleep(50_000)
    }
    fail("timed out waiting for #\(args[3]) == \"\(args[4])\"")
case "frame":
    guard args.count == 4, let element = find(app, args[3]),
          let position = attr(element, kAXPositionAttribute), let size = attr(element, kAXSizeAttribute)
    else { fail("no frame for #\(args.count > 3 ? args[3] : "")") }
    var origin = CGPoint.zero, extent = CGSize.zero
    guard AXValueGetValue(axValue(position, of: args[3]), .cgPoint, &origin),
          AXValueGetValue(axValue(size, of: args[3]), .cgSize, &extent)
    else { fail("no frame for #\(args[3])") }
    print(Int(origin.x), Int(origin.y), Int(extent.width), Int(extent.height))
case "window-id":
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let window = list.first {
        ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
    }
    guard let number = window?[kCGWindowNumber as String] else { fail("no on-screen window for pid \(pid)") }
    print(number)
default:
    fail("unknown command \(args[2])")
}
