import SwiftUI

@main
struct HotPotatoApp: App {
    var body: some Scene {
        WindowGroup("Hot Potato") {
            ContentView()
                .frame(minWidth: 820, minHeight: 600)
                .preferredColorScheme(.dark)
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

let palette: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .blue, .indigo, .purple, .pink, .brown, .cyan]

struct ContentView: View {
    @StateObject private var m = Model()
    @FocusState private var typingName: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35 + 0.4 * m.focus)
                .ignoresSafeArea()

            HStack(spacing: 20) {
                VStack(spacing: 28) {
                    WheelAssembly(names: m.turns.wheel, pose: m.pose,
                                  onDrag: m.drag(to:at:), onRelease: m.release)
                        .accessibilityElement()
                        .accessibilityIdentifier("wheel")
                        .accessibilityValue(m.spinning ? "spinning" : "idle")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { m.spin() }
                        .overlay {
                            Text(m.winner ?? " ")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32).padding(.vertical, 14)
                                .glassEffect(.regular, in: .capsule)
                                .opacity(m.winner == nil ? 0 : 1)
                                .scaleEffect(m.winner == nil ? 0.3 : 1)
                                .accessibilityIdentifier("winner")
                        }
                        .scaleEffect(1 + 0.06 * m.focus)
                        .zIndex(1)
                        .onTapGesture { m.spin() }

                    GlassEffectContainer {
                        HStack(spacing: 12) {
                            Button("Spin") { m.spin() }
                                .keyboardShortcut(.space, modifiers: [])
                                .disabled(m.spinning || m.turns.waiting.isEmpty)
                                .buttonStyle(.glassProminent)
                                .accessibilityIdentifier("spin")
                            Button("Reset") { m.reset() }
                                .disabled(m.spinning)
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("reset")
                        }
                        .controlSize(.extraLarge)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Team").font(.title3.bold())
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(m.team.names, id: \.self) { name in
                                HStack {
                                    Text(name)
                                        .strikethrough(m.turns.done.contains(name))
                                        .opacity(m.turns.done.contains(name) ? 0.5 : 1)
                                        .accessibilityIdentifier("member-\(name)")
                                        .accessibilityValue(m.turns.done.contains(name) ? "done" : "waiting")
                                    Spacer()
                                    Button { m.remove(name) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless)
                                        .disabled(m.spinning)
                                        .accessibilityIdentifier("remove-\(name)")
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            }
                        }
                    }
                    HStack {
                        TextField("Add name", text: $m.newName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                            .focused($typingName)
                            .accessibilityIdentifier("name-field")
                            .onSubmit(m.add)
                        Button { m.add() } label: { Image(systemName: "plus") }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("add")
                    }
                }
                .padding(16)
                .frame(width: 250)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .opacity(1 - 0.6 * m.focus)
            }
            .padding(24)
        }
        .onAppear {
            m.reset()
            // macOS focuses the text field at launch, which would swallow Space.
            DispatchQueue.main.async { typingName = false }
        }
    }
}

struct WheelAssembly: View {
    private let hubDeadZone = 0.12
    @GestureState private var dragging = false
    let names: [String]
    let pose: WheelPose
    var onDrag: (Double, Date) -> Void = { _, _ in }
    var onRelease: () -> Void = {}

    var body: some View {
        GeometryReader { g in
            let size = min(g.size.width, g.size.height)
            let rim = size * 0.035
            let face = size - rim * 2
            ZStack {
                Rim(rimWidth: rim)
                WheelFace(names: names)
                    .frame(width: face, height: face)
                    .rotationEffect(.radians(pose.clockwiseAngle))
                Hub(size: size * 0.1)
                Flapper(pose: pose, faceRadius: face / 2)
            }
            .frame(width: size, height: size)
            .position(x: g.size.width / 2, y: g.size.height / 2)
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { v in
                    let x = v.location.x - g.size.width / 2, y = v.location.y - g.size.height / 2
                    if x * x + y * y > pow(size * hubDeadZone, 2) { onDrag(atan2(y, x), v.time) }
                }
                .updating($dragging) { _, isDragging, _ in isDragging = true })
            .onChange(of: dragging) { _, stillDragging in if !stillDragging { onRelease() } }
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }
}

struct Rim: View {
    let rimWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            ctx.fill(Path(ellipseIn: rect), with: .linearGradient(
                Gradient(colors: [Color(white: 0.85), Color(white: 0.45), Color(white: 0.7), Color(white: 0.3)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)), with: .color(.white.opacity(0.3)), lineWidth: 1)
            let inner = rect.insetBy(dx: rimWidth, dy: rimWidth)
            ctx.fill(Path(ellipseIn: inner.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(0.4)))

        }
    }
}

struct Hub: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.95), Color(white: 0.7), Color(white: 0.4)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            Circle().stroke(.white.opacity(0.6), lineWidth: 1).padding(1)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

struct Flapper: View {
    let pose: WheelPose
    let faceRadius: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let r = faceRadius
            let points = WheelRadii.flapper(rootFromVertical: pose.rootFromVertical, tipFromVertical: pose.tipFromVertical)
            func onScreen(_ p: YDownPoint) -> CGPoint { CGPoint(x: size.width / 2 + p.x * r, y: size.height / 2 + p.y * r) }
            let pivot = onScreen(points.pivot), joint = onScreen(points.joint), end = onScreen(points.tip)
            func direction(_ a: CGPoint, _ b: CGPoint) -> CGVector {
                let length = hypot(b.x - a.x, b.y - a.y)
                return CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
            }
            let rootDir = direction(pivot, joint), tipDir = direction(joint, end)
            let tipW = WheelRadii.armRadius * r, rootW = tipW * 2.4, midW = (tipW + rootW) / 2
            func side(_ p: CGPoint, _ d: CGVector, _ w: CGFloat) -> CGPoint { CGPoint(x: p.x - d.dy * w, y: p.y + d.dx * w) }
            let jointDir = CGVector(dx: (rootDir.dx + tipDir.dx) / 2, dy: (rootDir.dy + tipDir.dy) / 2)

            var p = Path()
            p.move(to: side(pivot, rootDir, rootW))
            p.addLine(to: side(joint, jointDir, midW))
            p.addLine(to: side(end, tipDir, tipW))
            p.addArc(center: end, radius: tipW, startAngle: .radians(pose.tipFromVertical + .pi), endAngle: .radians(pose.tipFromVertical), clockwise: true)
            p.addLine(to: side(joint, jointDir, -midW))
            p.addLine(to: side(pivot, rootDir, -rootW))
            p.closeSubpath()
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2))
                l.fill(p, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.75)]),
                                                startPoint: CGPoint(x: pivot.x - rootW, y: pivot.y), endPoint: CGPoint(x: pivot.x + rootW, y: pivot.y)))
            }
            let capR = rootW * 1.5
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.5), radius: 1.5, y: 1))
                l.fill(Path(ellipseIn: CGRect(x: pivot.x - capR, y: pivot.y - capR, width: capR * 2, height: capR * 2)),
                       with: .radialGradient(Gradient(colors: [Color(white: 0.95), Color(white: 0.55)]),
                                             center: CGPoint(x: pivot.x - capR * 0.3, y: pivot.y - capR * 0.3), startRadius: 0, endRadius: capR * 1.2))
            }
        }
        .allowsHitTesting(false)
    }
}

struct WheelFace: View {
    let names: [String]

    var body: some View {
        Canvas { ctx, size in
            let r = size.width / 2
            let c = CGPoint(x: r, y: r)
            let disc = Path(ellipseIn: CGRect(origin: .zero, size: size))
            guard !names.isEmpty else {
                ctx.fill(disc, with: .color(Color(white: 0.2)))
                return
            }
            for i in names.indices {
                var p = Path()
                p.move(to: c)
                p.addArc(center: c, radius: r, startAngle: .radians(WheelRadii.sliceAngle(i, of: names.count)), endAngle: .radians(WheelRadii.sliceAngle(i + 1, of: names.count)), clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(palette[i % palette.count]))
            }
            ctx.fill(disc, with: .radialGradient(Gradient(colors: [.white.opacity(0.08), .clear, .black.opacity(0.18)]),
                                                 center: c, startRadius: 0, endRadius: r))

            for (i, name) in names.enumerated() {
                var t = ctx
                t.translateBy(x: c.x, y: c.y)
                t.rotate(by: .radians((WheelRadii.sliceAngle(i, of: names.count) + WheelRadii.sliceAngle(i + 1, of: names.count)) / 2))
                let fontSize = min(24, max(11, r / CGFloat(max(names.count, 4)) * 0.9))
                let text = Text(name).font(.system(size: fontSize, weight: .heavy, design: .rounded)).foregroundColor(.white)
                t.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1))
                    l.draw(text, at: CGPoint(x: r * 0.82, y: 0), anchor: .trailing)
                }
            }

            for i in 0..<names.count {
                let a = WheelRadii.sliceAngle(i, of: names.count)
                var line = Path()
                line.move(to: c)
                line.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                ctx.stroke(line, with: .color(.white.opacity(0.7)), lineWidth: 1.5)

                let pegR = r * WheelRadii.pegRadius
                let peg = WheelRadii.peg(i, of: names.count)
                let pc = CGPoint(x: c.x + peg.x * r, y: c.y + peg.y * r)
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pegR + 1, y: pc.y - pegR + 2, width: pegR * 2, height: pegR * 2)), with: .color(.black.opacity(0.4)))
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pegR, y: pc.y - pegR, width: pegR * 2, height: pegR * 2)), with: .radialGradient(
                    Gradient(colors: [.white, Color(white: 0.6)]),
                    center: CGPoint(x: pc.x - pegR * 0.35, y: pc.y - pegR * 0.35), startRadius: 0, endRadius: pegR * 1.3))
            }
            ctx.stroke(disc, with: .color(.black.opacity(0.5)), lineWidth: 2)
        }
    }
}
