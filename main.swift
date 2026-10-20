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
    @StateObject private var model = Model()
    @FocusState private var typingName: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35 + 0.4 * model.focus)
                .ignoresSafeArea()
            HStack(spacing: 20) {
                WheelColumn(model: model)
                TeamPanel(model: model, typingName: $typingName)
            }
            .padding(24)
        }
        .onAppear {
            // macOS focuses the text field at launch, which would swallow Space.
            DispatchQueue.main.async { typingName = false }
        }
    }
}

struct WheelColumn: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(spacing: 28) {
            WheelAssembly(names: model.turns.wheel.map(\.text), pose: model.pose, onDrag: model.drag(to:at:), onRelease: model.release)
                .accessibilityElement()
                .accessibilityIdentifier("wheel")
                .accessibilityValue(model.spinning ? "spinning" : "idle")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.spin() }
                .overlay { WinnerBanner(winner: model.winner?.text) }
                .scaleEffect(1 + 0.06 * model.focus)
                .zIndex(1)
                .onTapGesture { model.spin() }
            GlassEffectContainer {
                HStack(spacing: 12) {
                    Button("Spin") { model.spin() }
                        .keyboardShortcut(.space, modifiers: [])
                        .disabled(model.spinning || model.turns.waiting.isEmpty)
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("spin")
                    Button("Reset") { model.reset() }
                        .disabled(model.spinning)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("reset")
                }
                .controlSize(.extraLarge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WinnerBanner: View {
    let winner: String?

    var body: some View {
        Text(winner ?? " ")
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 32).padding(.vertical, 14)
            .glassEffect(.regular, in: .capsule)
            .opacity(winner == nil ? 0 : 1)
            .scaleEffect(winner == nil ? 0.3 : 1)
            .accessibilityIdentifier("winner")
    }
}

struct TeamPanel: View {
    @ObservedObject var model: Model
    var typingName: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Team").font(.title3.bold())
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.team.names, id: \.self) { name in
                        MemberRow(name: name.text, done: model.turns.done.contains(name), removable: !model.spinning) { model.remove(name) }
                    }
                }
            }
            HStack {
                TextField("Add name", text: $model.newName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .focused(typingName)
                    .accessibilityIdentifier("name-field")
                    .onSubmit(model.add)
                Button { model.add() } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("add")
            }
        }
        .padding(16)
        .frame(width: 250)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .opacity(1 - 0.6 * model.focus)
    }
}

struct MemberRow: View {
    let name: String
    let done: Bool
    let removable: Bool
    let remove: () -> Void

    var body: some View {
        HStack {
            Text(name)
                .strikethrough(done)
                .opacity(done ? 0.5 : 1)
                .accessibilityIdentifier("member-\(name)")
                .accessibilityValue(done ? "done" : "waiting")
            Spacer()
            Button(action: remove) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .disabled(!removable)
                .accessibilityIdentifier("remove-\(name)")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
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
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
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
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { drag in
                    let fromCenterX = drag.location.x - geometry.size.width / 2, fromCenterY = drag.location.y - geometry.size.height / 2
                    if fromCenterX * fromCenterX + fromCenterY * fromCenterY > pow(size * hubDeadZone, 2) { onDrag(atan2(fromCenterY, fromCenterX), drag.time) }
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
            let points = WheelRadii.flapper(rootFromVertical: pose.rootFromVertical, tipFromVertical: pose.tipFromVertical)
            func onScreen(_ point: YDownPoint) -> CGPoint { CGPoint(x: size.width / 2 + point.x * faceRadius, y: size.height / 2 + point.y * faceRadius) }
            let pivot = onScreen(points.pivot)
            let rootWidth = WheelRadii.armRadius * faceRadius * 2.4
            drawArm(outline(pivot: pivot, joint: onScreen(points.joint), end: onScreen(points.tip)), pivot: pivot, rootWidth: rootWidth, in: ctx)
            drawPivotCap(at: pivot, radius: rootWidth * 1.5, in: ctx)
        }
        .allowsHitTesting(false)
    }

    private func outline(pivot: CGPoint, joint: CGPoint, end: CGPoint) -> Path {
        func direction(_ start: CGPoint, _ end: CGPoint) -> CGVector {
            let length = hypot(end.x - start.x, end.y - start.y)
            return CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
        }
        func side(_ point: CGPoint, _ heading: CGVector, _ offset: CGFloat) -> CGPoint {
            CGPoint(x: point.x - heading.dy * offset, y: point.y + heading.dx * offset)
        }
        let rootDir = direction(pivot, joint), tipDir = direction(joint, end)
        let jointDir = CGVector(dx: (rootDir.dx + tipDir.dx) / 2, dy: (rootDir.dy + tipDir.dy) / 2)
        let tipW = WheelRadii.armRadius * faceRadius, rootW = tipW * 2.4, midW = (tipW + rootW) / 2
        var path = Path()
        path.move(to: side(pivot, rootDir, rootW))
        path.addLine(to: side(joint, jointDir, midW))
        path.addLine(to: side(end, tipDir, tipW))
        path.addArc(center: end, radius: tipW, startAngle: .radians(pose.tipFromVertical + .pi), endAngle: .radians(pose.tipFromVertical), clockwise: true)
        path.addLine(to: side(joint, jointDir, -midW))
        path.addLine(to: side(pivot, rootDir, -rootW))
        path.closeSubpath()
        return path
    }

    private func drawArm(_ arm: Path, pivot: CGPoint, rootWidth: CGFloat, in ctx: GraphicsContext) {
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2))
            layer.fill(arm, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.75)]),
                                              startPoint: CGPoint(x: pivot.x - rootWidth, y: pivot.y), endPoint: CGPoint(x: pivot.x + rootWidth, y: pivot.y)))
        }
    }

    private func drawPivotCap(at pivot: CGPoint, radius capR: CGFloat, in ctx: GraphicsContext) {
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 1.5, y: 1))
            layer.fill(Path(ellipseIn: CGRect(x: pivot.x - capR, y: pivot.y - capR, width: capR * 2, height: capR * 2)),
                   with: .radialGradient(Gradient(colors: [Color(white: 0.95), Color(white: 0.55)]),
                                         center: CGPoint(x: pivot.x - capR * 0.3, y: pivot.y - capR * 0.3), startRadius: 0, endRadius: capR * 1.2))
        }
    }
}

struct WheelFace: View {
    let names: [String]

    var body: some View {
        Canvas { ctx, size in
            let radius = size.width / 2
            let center = CGPoint(x: radius, y: radius)
            let disc = Path(ellipseIn: CGRect(origin: .zero, size: size))
            guard !names.isEmpty else {
                ctx.fill(disc, with: .color(Color(white: 0.2)))
                return
            }
            drawSlices(center: center, radius: radius, in: ctx)
            ctx.fill(disc, with: .radialGradient(Gradient(colors: [.white.opacity(0.08), .clear, .black.opacity(0.18)]),
                                                 center: center, startRadius: 0, endRadius: radius))
            drawNames(center: center, radius: radius, in: ctx)
            drawDividersAndPegs(center: center, radius: radius, in: ctx)
            ctx.stroke(disc, with: .color(.black.opacity(0.5)), lineWidth: 2)
        }
    }

    private func angle(_ index: Int) -> Double { WheelRadii.sliceAngle(index, of: names.count) }

    private func drawSlices(center: CGPoint, radius: CGFloat, in ctx: GraphicsContext) {
        for index in names.indices {
            var path = Path()
            path.move(to: center)
            path.addArc(center: center, radius: radius, startAngle: .radians(angle(index)), endAngle: .radians(angle(index + 1)), clockwise: false)
            path.closeSubpath()
            ctx.fill(path, with: .color(palette[index % palette.count]))
        }
    }

    private func drawNames(center: CGPoint, radius: CGFloat, in ctx: GraphicsContext) {
        let fontSize = min(24, max(11, radius / CGFloat(max(names.count, 4)) * 0.9))
        for (index, name) in names.enumerated() {
            var rotated = ctx
            rotated.translateBy(x: center.x, y: center.y)
            rotated.rotate(by: .radians((angle(index) + angle(index + 1)) / 2))
            let text = Text(name).font(.system(size: fontSize, weight: .heavy, design: .rounded)).foregroundColor(.white)
            rotated.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1))
                layer.draw(text, at: CGPoint(x: radius * 0.82, y: 0), anchor: .trailing)
            }
        }
    }

    private func drawDividersAndPegs(center: CGPoint, radius: CGFloat, in ctx: GraphicsContext) {
        let pegR = radius * WheelRadii.pegRadius
        for index in 0..<names.count {
            var line = Path()
            line.move(to: center)
            line.addLine(to: CGPoint(x: center.x + cos(angle(index)) * radius, y: center.y + sin(angle(index)) * radius))
            ctx.stroke(line, with: .color(.white.opacity(0.7)), lineWidth: 1.5)

            let peg = WheelRadii.peg(index, of: names.count)
            let pegCenter = CGPoint(x: center.x + peg.x * radius, y: center.y + peg.y * radius)
            ctx.fill(Path(ellipseIn: CGRect(x: pegCenter.x - pegR + 1, y: pegCenter.y - pegR + 2, width: pegR * 2, height: pegR * 2)), with: .color(.black.opacity(0.4)))
            ctx.fill(Path(ellipseIn: CGRect(x: pegCenter.x - pegR, y: pegCenter.y - pegR, width: pegR * 2, height: pegR * 2)), with: .radialGradient(
                Gradient(colors: [.white, Color(white: 0.6)]),
                center: CGPoint(x: pegCenter.x - pegR * 0.35, y: pegCenter.y - pegR * 0.35), startRadius: 0, endRadius: pegR * 1.3))
        }
    }
}
