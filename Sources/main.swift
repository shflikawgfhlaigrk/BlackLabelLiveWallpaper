import Cocoa
import SwiftUI

// ============================================================================
// Black Label — Live Wallpaper  (premium pass)
// Principle: match the original render's expensive 3D-gold quality. Motion comes
// from moving the REAL artwork pixels + premium light — never cheap vector shapes.
//   • building turntable  (rotates the real tower pixels)
//   • spinning gears      (rotates the real gear pixels, clipped in place)
//   • energy pulses       (soft light traveling along the gold circuit traces)
//   • metallic glint      (specular sweep across the gold)
//   • emblem core + unlock shockwave (light blooms, with a vibration on unlock)
// Gibberish is hidden under frosted-glass panels matching the art's dark panels.
// ============================================================================

private let gold       = Color(red: 0.82, green: 0.64, blue: 0.28)
private let brightGold = Color(red: 0.98, green: 0.86, blue: 0.52)
private let deepGlass1  = Color(red: 0.07, green: 0.075, blue: 0.10)
private let deepGlass2  = Color(red: 0.02, green: 0.025, blue: 0.045)

private let leftApps  = ["LEADS", "REAL ESTATE", "MARKETING"]
private let rightApps = ["TRADING", "SOVEREIGN", "HOMEFRONT"]

private func loadBase() -> NSImage? {
    if let u = Bundle.main.url(forResource: "wallpaper", withExtension: "png"),
       let img = NSImage(contentsOf: u) { return img }
    return NSImage(contentsOfFile: NSHomeDirectory() + "/Pictures/BlackLabelBots_wallpaper_5504x3072.png")
}
private let baseImage: NSImage? = loadBase()
private let imgAspect: CGFloat = 5504.0 / 3072.0
private var forcedTime: Double? = nil

private struct Fit { var x: CGFloat; var y: CGFloat; var w: CGFloat; var h: CGFloat }
private func fitRect(_ size: CGSize, _ fill: Bool) -> Fit {
    let scrA = size.width / max(size.height, 1)
    let matchWidth = fill ? (scrA >= imgAspect) : (scrA <= imgAspect)
    if matchWidth { let w = size.width, h = w / imgAspect; return Fit(x: 0, y: (size.height - h) / 2, w: w, h: h) }
    else { let h = size.height, w = h * imgAspect; return Fit(x: (size.width - w) / 2, y: 0, w: w, h: h) }
}

// MARK: - Minimal 3D for holograms (real rotation, projected wireframe)
private struct V3 { var x: Double; var y: Double; var z: Double }
private func rotY(_ p: V3, _ a: Double) -> V3 { let c = cos(a), s = sin(a); return V3(x: p.x * c + p.z * s, y: p.y, z: -p.x * s + p.z * c) }
private func rotX(_ p: V3, _ a: Double) -> V3 { let c = cos(a), s = sin(a); return V3(x: p.x, y: p.y * c - p.z * s, z: p.y * s + p.z * c) }
private func rotZ(_ p: V3, _ a: Double) -> V3 { let c = cos(a), s = sin(a); return V3(x: p.x * c - p.y * s, y: p.x * s + p.y * c, z: p.z) }

private func gearEdges(_ teeth: Int, _ rTip: Double, _ rRoot: Double, _ depth: Double, _ hubR: Double) -> [(V3, V3)] {
    var prof: [(Double, Double)] = []
    for i in 0..<teeth {
        let base = Double(i) * 2 * Double.pi / Double(teeth), pitch = 2 * Double.pi / Double(teeth)
        let tipH = pitch * 0.28, rootH = pitch * 0.46
        for (a, r) in [(base - rootH, rRoot), (base - tipH, rTip), (base + tipH, rTip), (base + rootH, rRoot)] {
            prof.append((r * cos(a), r * sin(a)))
        }
    }
    let d = depth / 2; var e: [(V3, V3)] = []; let n = prof.count
    for i in 0..<n {
        let p = prof[i], q = prof[(i + 1) % n]
        e.append((V3(x: p.0, y: p.1, z: d), V3(x: q.0, y: q.1, z: d)))        // front rim
        e.append((V3(x: p.0, y: p.1, z: -d), V3(x: q.0, y: q.1, z: -d)))      // back rim
        e.append((V3(x: p.0, y: p.1, z: d), V3(x: p.0, y: p.1, z: -d)))       // connector
    }
    let hn = 6; var hub: [(Double, Double)] = []
    for i in 0..<hn { let a = Double(i) * 2 * Double.pi / Double(hn); hub.append((hubR * cos(a), hubR * sin(a))) }
    for i in 0..<hn {
        let p = hub[i], q = hub[(i + 1) % hn]
        e.append((V3(x: p.0, y: p.1, z: d), V3(x: q.0, y: q.1, z: d)))
        e.append((V3(x: p.0, y: p.1, z: -d), V3(x: q.0, y: q.1, z: -d)))
        e.append((V3(x: p.0, y: p.1, z: d), V3(x: p.0, y: p.1, z: -d)))
    }
    for k in 0..<3 {                                                          // spokes
        let a = Double(k) * 2 * Double.pi / 3
        e.append((V3(x: hubR * cos(a), y: hubR * sin(a), z: d), V3(x: rRoot * 0.92 * cos(a), y: rRoot * 0.92 * sin(a), z: d)))
    }
    return e
}

private func boxEdges(_ hw: Double, _ y0: Double, _ y1: Double) -> [(V3, V3)] {
    let b = [V3(x: -hw, y: y0, z: -hw), V3(x: hw, y: y0, z: -hw), V3(x: hw, y: y0, z: hw), V3(x: -hw, y: y0, z: hw)]
    let tp = [V3(x: -hw, y: y1, z: -hw), V3(x: hw, y: y1, z: -hw), V3(x: hw, y: y1, z: hw), V3(x: -hw, y: y1, z: hw)]
    var e: [(V3, V3)] = []
    for i in 0..<4 { e.append((b[i], b[(i + 1) % 4])); e.append((tp[i], tp[(i + 1) % 4])); e.append((b[i], tp[i])) }
    return e
}
private func towerEdges() -> [(V3, V3)] {
    var e: [(V3, V3)] = []
    let tiers: [(Double, Double, Double)] = [(1.0, 0, 1.0), (0.72, 1.0, 2.0), (0.5, 2.0, 2.9), (0.32, 2.9, 3.5), (0.18, 3.5, 3.95)]
    for (hw, y0, y1) in tiers {
        e += boxEdges(hw, y0, y1)
        let fy = y0 + (y1 - y0) * 0.5                                  // a mid "floor" ring for detail
        let c = [V3(x: -hw, y: fy, z: -hw), V3(x: hw, y: fy, z: -hw), V3(x: hw, y: fy, z: hw), V3(x: -hw, y: fy, z: hw)]
        for i in 0..<4 { e.append((c[i], c[(i + 1) % 4])) }
    }
    let apex = V3(x: 0, y: 4.45, z: 0), antenna = V3(x: 0, y: 5.1, z: 0)
    let top = [V3(x: -0.18, y: 3.95, z: -0.18), V3(x: 0.18, y: 3.95, z: -0.18), V3(x: 0.18, y: 3.95, z: 0.18), V3(x: -0.18, y: 3.95, z: 0.18)]
    for c in top { e.append((c, apex)) }
    e.append((apex, antenna))
    return e
}
private func sphereEdges(_ r: Double, _ lat: Int, _ lon: Int, _ seg: Int) -> [(V3, V3)] {
    var e: [(V3, V3)] = []
    for i in 1..<lat {
        let phi = -Double.pi / 2 + Double.pi * Double(i) / Double(lat)
        let rr = r * cos(phi), y = r * sin(phi)
        var prev = V3(x: rr, y: y, z: 0)
        for s in 1...seg { let a = 2 * Double.pi * Double(s) / Double(seg); let p = V3(x: rr * cos(a), y: y, z: rr * sin(a)); e.append((prev, p)); prev = p }
    }
    for j in 0..<lon {
        let lng = 2 * Double.pi * Double(j) / Double(lon)
        var prev = V3(x: 0, y: -r, z: 0)
        for s in 1...seg { let phi = -Double.pi / 2 + Double.pi * Double(s) / Double(seg); let rr = r * cos(phi), y = r * sin(phi); let p = V3(x: rr * cos(lng), y: y, z: rr * sin(lng)); e.append((prev, p)); prev = p }
    }
    return e
}
private func octaEdges(_ r: Double) -> [(V3, V3)] {
    let v = [V3(x: r, y: 0, z: 0), V3(x: -r, y: 0, z: 0), V3(x: 0, y: r, z: 0), V3(x: 0, y: -r, z: 0), V3(x: 0, y: 0, z: r), V3(x: 0, y: 0, z: -r)]
    let pairs = [(0, 2), (0, 3), (0, 4), (0, 5), (1, 2), (1, 3), (1, 4), (1, 5), (2, 4), (4, 3), (3, 5), (5, 2)]
    return pairs.map { (v[$0.0], v[$0.1]) }
}

// Pauses the render clock whenever nothing can be seen: window fully occluded,
// screen locked, or displays asleep. A desktop-level window otherwise redraws at
// 30 fps forever (~1 core, both displays) even under a wall of app windows.
final class RenderGate: ObservableObject {
    @Published var paused = false
}

struct WallpaperView: View {
    var fill: Bool = false
    @ObservedObject var gate = RenderGate()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: gate.paused)) { tl in
            let t = forcedTime ?? tl.date.timeIntervalSinceReferenceDate
            let u = unlockState(t)
            ZStack {
                Color.black
                if let img = baseImage {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                }
                Canvas { ctx, size in draw(ctx, size, t, u) }
            }
            .offset(x: u.sx, y: u.sy)        // vibration only — no breathing (that read as "liquid")
            .clipped()
            .ignoresSafeArea()
        }
    }

    // MARK: helpers
    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    private func glow(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color, _ a: Double) {
        ctx.fill(circle(c, r), with: .radialGradient(Gradient(colors: [color.opacity(a), .clear]),
                                                     center: c, startRadius: 0, endRadius: r))
    }
    private func emboss(_ ctx: GraphicsContext, _ s: String, _ at: CGPoint, _ size: CGFloat,
                        _ weight: Font.Weight, tracking: CGFloat = 0) {
        func mk(_ col: Color) -> Text {
            var x = Text(s).font(.system(size: max(1, size), weight: weight, design: .rounded)).foregroundColor(col)
            if tracking != 0 { x = x.tracking(tracking) }; return x
        }
        ctx.draw(mk(Color.black.opacity(0.6)), at: CGPoint(x: at.x, y: at.y + size * 0.045), anchor: .center)
        ctx.draw(mk(brightGold), at: at, anchor: .center)
    }
    // frosted-glass panel matching the art's dark panels (gold-beveled)
    private func glassPanel(_ ctx: GraphicsContext, _ r: CGRect) {
        let rad = r.height * 0.13
        let rr = Path(roundedRect: r, cornerRadius: rad)
        ctx.fill(rr, with: .linearGradient(Gradient(colors: [deepGlass1, deepGlass2]),
                                           startPoint: CGPoint(x: r.midX, y: r.minY),
                                           endPoint: CGPoint(x: r.midX, y: r.maxY)))
        // top inner sheen
        let sheen = Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.4), cornerRadius: rad)
        ctx.fill(sheen, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.05), .clear]),
                                              startPoint: CGPoint(x: r.midX, y: r.minY),
                                              endPoint: CGPoint(x: r.midX, y: r.minY + r.height * 0.4)))
        // beveled gold border
        ctx.stroke(rr, with: .linearGradient(Gradient(colors: [brightGold.opacity(0.85), gold.opacity(0.25)]),
                                             startPoint: CGPoint(x: r.midX, y: r.minY),
                                             endPoint: CGPoint(x: r.midX, y: r.maxY)),
                   lineWidth: max(1, r.height * 0.018))
    }

    // MARK: unlock cycle
    private func unlockState(_ t: TimeInterval) -> (charge: Double, burst: Double, sx: CGFloat, sy: CGFloat) {
        let T = 8.0, ph = t.truncatingRemainder(dividingBy: T)
        var charge = 0.0, burst = -1.0
        var sx: CGFloat = 0, sy: CGFloat = 0
        if ph < 3.0 { charge = ph / 3.0 }
        else if ph < 3.3 { charge = 1.0 }
        else if ph < 5.0 {
            burst = (ph - 3.3) / 1.7
            charge = max(0, 1.0 - (ph - 3.3) / 0.6)
            if ph < 3.85 {
                let decay = CGFloat(1 - (ph - 3.3) / 0.55)
                sx = 5 * decay * CGFloat(sin(t * 88)); sy = 4 * decay * CGFloat(cos(t * 80))
            }
        }
        return (charge, burst, sx, sy)
    }

    // MARK: main
    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: TimeInterval,
                      _ u: (charge: Double, burst: Double, sx: CGFloat, sy: CGFloat)) {
        let f = fitRect(size, fill)
        func P(_ uu: CGFloat, _ vv: CGFloat) -> CGPoint { CGPoint(x: f.x + uu * f.w, y: f.y + vv * f.h) }
        func S(_ s: CGFloat) -> CGFloat { f.h * s }
        func nrect(_ u0: CGFloat, _ v0: CGFloat, _ u1: CGFloat, _ v1: CGFloat) -> CGRect {
            let a = P(u0, v0), b = P(u1, v1); return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        }
        // 1) holographic spinning gears (3D wireframe, matches the holo language)
        holoGears(ctx, P, S, t)

        // 2) HOLOGRAMS — real 3D wireframe, truly rotating (the wow)
        holoTower(ctx, center: P(0.842, 0.300), scale: S(0.060), baseR: S(0.235), t: t)   // spinning holo skyscraper
        // holo data globe (top-right) — dark glass panel hides the gibberish, hologram projects inside
        glassPanel(ctx, nrect(0.702, 0.048, 0.818, 0.188))
        renderHolo(ctx, center: P(0.760, 0.118), scale: S(0.050), baseR: S(0.090),
                   angle: t * 0.6, tilt: 0.42, yOffset: 0, lw: max(0.9, S(0.0016)),
                   suppress: false, edges: sphereEdges(1.0, 5, 8, 16), t: t)
        // holo crystal (left)
        glassPanel(ctx, nrect(0.044, 0.668, 0.182, 0.808))
        renderHolo(ctx, center: P(0.113, 0.738), scale: S(0.052), baseR: S(0.090),
                   angle: t * 0.7, tilt: 0.5, yOffset: 0, lw: max(0.9, S(0.0016)),
                   suppress: false, edges: octaEdges(1.0), t: t)

        // 3) badge stays a clean glass readout
        let badge = nrect(0.182, 0.045, 0.310, 0.168)
        glassPanel(ctx, badge)
        emboss(ctx, "98", CGPoint(x: badge.midX, y: badge.minY + badge.height * 0.40), badge.height * 0.46, .heavy)
        emboss(ctx, "GROWTH SCORE", CGPoint(x: badge.midX, y: badge.minY + badge.height * 0.74), badge.height * 0.15, .semibold, tracking: badge.height * 0.012)

        // 3) emblem energy core (charges before unlock)
        let gc = P(0.5, 0.33)
        glow(ctx, gc, S(0.22), brightGold, 0.10 + 0.07 * (0.5 + 0.5 * sin(t * 0.7)) + u.charge * 0.55)

        // 4) energy pulses — soft light comets along the gold traces
        let traces: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.020, 0.30, 0.175, 0.30), (0.020, 0.46, 0.150, 0.46), (0.020, 0.62, 0.140, 0.62),
            (0.980, 0.30, 0.825, 0.30), (0.980, 0.46, 0.850, 0.46), (0.980, 0.62, 0.860, 0.62),
            (0.300, 0.050, 0.300, 0.185), (0.700, 0.050, 0.700, 0.185),
            (0.120, 0.170, 0.120, 0.600), (0.880, 0.170, 0.880, 0.600),
            (0.500, 0.150, 0.420, 0.300), (0.500, 0.150, 0.580, 0.300)]
        for (ti, tr) in traces.enumerated() {
            let prog = CGFloat((t * 0.30 + Double(ti) * 0.16).truncatingRemainder(dividingBy: 1))
            let a = P(tr.0, tr.1), b = P(tr.2, tr.3)
            let head = CGPoint(x: a.x + (b.x - a.x) * prog, y: a.y + (b.y - a.y) * prog)
            glow(ctx, head, S(0.018), brightGold, 0.7 * Double(1 - prog) + 0.2)   // soft bloom head
            for k in 1..<4 {
                let s = max(0, prog - CGFloat(k) * 0.035)
                let p = CGPoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
                glow(ctx, p, S(0.009), brightGold, 0.25 * Double(4 - k) / 4)
            }
        }

        // 5) metallic glint — a narrow specular sweep across the gold (periodic, quick)
        let gph = (t * 0.5).truncatingRemainder(dividingBy: 1)     // sweep ~every 2s
        if gph < 0.45 {
            let gx = f.x - f.w * 0.1 + (f.w * 1.2) * CGFloat(gph / 0.45)
            let band = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [.clear, Color.white.opacity(0.10), brightGold.opacity(0.10), .clear]),
                startPoint: CGPoint(x: gx - f.w * 0.05, y: f.y),
                endPoint: CGPoint(x: gx + f.w * 0.05, y: f.y + f.h))
            ctx.fill(Path(CGRect(x: f.x, y: f.y, width: f.w, height: f.h)), with: band)
        }

        // 6) clean 6-app row (real words + Homefront), embossed
        drawPills(ctx, f)

        // 7) unlock shockwave bloom
        if u.burst >= 0 {
            let lc = P(0.5, 0.30)
            let maxR = (size.width * size.width + size.height * size.height).squareRoot() * 0.62
            for ring in 0..<3 {
                let bp = u.burst - Double(ring) * 0.09
                if bp > 0, bp < 1 {
                    let rr = maxR * CGFloat(bp)
                    ctx.stroke(circle(lc, rr), with: .color(brightGold.opacity((1 - bp) * 0.7)),
                               lineWidth: max(1, 12 * (1 - CGFloat(bp))))
                }
            }
            glow(ctx, lc, maxR * CGFloat(min(1, u.burst + 0.2)), brightGold, (1 - u.burst) * 0.18)
        }
    }

    // MARK: holograms
    private func renderHolo(_ ctx: GraphicsContext, center: CGPoint, scale: CGFloat, baseR: CGFloat,
                            angle: Double, tilt: Double, yOffset: Double, lw: CGFloat,
                            suppress: Bool = true, edges: [(V3, V3)], t: TimeInterval) {
        // suppress the static art behind the hologram (so the wireframe reads as a clean projection)
        if suppress {
            ctx.fill(circle(center, baseR), with: .radialGradient(
                Gradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.0)]),
                center: center, startRadius: baseR * 0.1, endRadius: baseR))
        }
        let flick = 0.82 + 0.18 * sin(t * 26)
        func pr(_ p0: V3) -> CGPoint {
            var p = rotY(V3(x: p0.x, y: p0.y - yOffset, z: p0.z), angle)
            p = rotX(p, tilt)
            let persp = 1.0 / (1.0 + p.z * 0.05)
            return CGPoint(x: center.x + CGFloat(p.x) * scale * CGFloat(persp),
                           y: center.y - CGFloat(p.y) * scale * CGFloat(persp))
        }
        for e in edges {
            let a = pr(e.0), b = pr(e.1)
            var ln = Path(); ln.move(to: a); ln.addLine(to: b)
            ctx.stroke(ln, with: .color(gold.opacity(0.20 * flick)), lineWidth: lw * 3.5)     // glow
            ctx.stroke(ln, with: .color(brightGold.opacity(0.95 * flick)), lineWidth: lw)      // core
        }
    }

    private func holoTower(_ ctx: GraphicsContext, center: CGPoint, scale: CGFloat, baseR: CGFloat, t: TimeInterval) {
        drawHoloGrid(ctx, CGPoint(x: center.x, y: center.y + scale * 2.0), baseR * 0.95, t)
        renderHolo(ctx, center: center, scale: scale, baseR: baseR, angle: t * 0.5, tilt: 0.22,
                   yOffset: 2.0, lw: max(1.4, scale * 0.045), edges: towerEdges(), t: t)
        // holographic scan line sweeping up the projection
        let frac = CGFloat((t * 0.35).truncatingRemainder(dividingBy: 1))
        let sy = (center.y + baseR * 0.8) - baseR * 1.6 * frac
        var sl = Path(); sl.move(to: CGPoint(x: center.x - baseR * 0.55, y: sy)); sl.addLine(to: CGPoint(x: center.x + baseR * 0.55, y: sy))
        ctx.stroke(sl, with: .color(brightGold.opacity(0.45 * Double(1 - frac))), lineWidth: max(1, scale * 0.025))
    }

    private func drawHoloGrid(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ t: TimeInterval) {
        let n = 6
        func iso(_ gx: CGFloat, _ gy: CGFloat) -> CGPoint { CGPoint(x: c.x + (gx - gy) * r * 0.62, y: c.y + (gx + gy) * r * 0.26) }
        let pulse = 0.18 + 0.10 * (0.5 + 0.5 * sin(t * 1.2))
        for i in 0...n {
            let g = CGFloat(i) / CGFloat(n) * 2 - 1
            var a = Path(); a.move(to: iso(-1, g)); a.addLine(to: iso(1, g))
            var b = Path(); b.move(to: iso(g, -1)); b.addLine(to: iso(g, 1))
            ctx.stroke(a, with: .color(gold.opacity(pulse)), lineWidth: 1)
            ctx.stroke(b, with: .color(gold.opacity(pulse)), lineWidth: 1)
        }
    }

    // MARK: holographic gears (3D wireframe, spinning on the axle, tilted for depth)
    private func holoGears(_ ctx: GraphicsContext, _ P: (CGFloat, CGFloat) -> CGPoint,
                           _ S: (CGFloat) -> CGFloat, _ t: TimeInterval) {
        // (u, v, radius·h, teeth, speed, dir) — emblem-corner gears
        let gears: [(CGFloat, CGFloat, CGFloat, Int, Double, Double)] = [
            (0.367, 0.160, 0.052, 12, 0.6, 1), (0.401, 0.224, 0.034, 10, 1.0, -1),
            (0.654, 0.160, 0.052, 12, 0.6, -1), (0.616, 0.224, 0.034, 10, 1.0, 1)]
        let flick = 0.82 + 0.18 * sin(t * 26), tilt = 0.5
        for g in gears {
            let c = P(g.0, g.1), scale = S(g.2), baseR = scale * 1.5
            ctx.fill(circle(c, baseR), with: .radialGradient(
                Gradient(stops: [.init(color: Color.black.opacity(0.96), location: 0),
                                 .init(color: Color.black.opacity(0.94), location: 0.7),
                                 .init(color: Color.black.opacity(0.0), location: 1)]),
                center: c, startRadius: 0, endRadius: baseR))
            let edges = gearEdges(g.3, 1.0, 0.78, 0.18, 0.34)
            let spin = t * g.4 * g.5
            func pr(_ p0: V3) -> CGPoint {
                let p = rotX(rotZ(p0, spin), tilt)
                let persp = 1.0 / (1.0 + p.z * 0.05)
                return CGPoint(x: c.x + CGFloat(p.x) * scale * CGFloat(persp),
                               y: c.y - CGFloat(p.y) * scale * CGFloat(persp))
            }
            for e in edges {
                let a = pr(e.0), b = pr(e.1)
                var ln = Path(); ln.move(to: a); ln.addLine(to: b)
                ctx.stroke(ln, with: .color(gold.opacity(0.20 * flick)), lineWidth: max(1.5, scale * 0.06))
                ctx.stroke(ln, with: .color(brightGold.opacity(0.95 * flick)), lineWidth: max(0.8, scale * 0.025))
            }
        }
    }

    // MARK: bottom pill row
    private func drawPills(_ ctx: GraphicsContext, _ f: Fit) {
        func P(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: f.x + u * f.w, y: f.y + v * f.h) }
        let vCenter: CGFloat = 0.887, pillH = f.h * 0.040
        for (u0, u1) in [(0.030, 0.375), (0.625, 0.970)] {
            let a = P(CGFloat(u0), vCenter - 0.030), b = P(CGFloat(u1), vCenter + 0.030)
            ctx.fill(Path(roundedRect: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y), cornerRadius: pillH * 0.4),
                     with: .linearGradient(Gradient(colors: [deepGlass1, deepGlass2]),
                                           startPoint: CGPoint(x: a.x, y: a.y), endPoint: CGPoint(x: a.x, y: b.y)))
        }
        layoutPills(ctx, leftApps, 0.045, 0.370, vCenter, pillH, f)
        layoutPills(ctx, rightApps, 0.630, 0.955, vCenter, pillH, f)
    }
    private func layoutPills(_ ctx: GraphicsContext, _ names: [String], _ u0: CGFloat, _ u1: CGFloat,
                             _ vCenter: CGFloat, _ pillH: CGFloat, _ f: Fit) {
        let fontSize = pillH * 0.42, yc = f.y + vCenter * f.h
        let padX = pillH * 0.7, gap = pillH * 0.5
        var widths: [CGFloat] = []
        for n in names {
            let m = ctx.resolve(Text(n).font(.system(size: fontSize, weight: .semibold, design: .rounded))).measure(in: CGSize(width: 10000, height: pillH))
            widths.append(m.width + padX * 2)
        }
        let total = widths.reduce(0, +) + gap * CGFloat(names.count - 1)
        var x = (f.x + u0 * f.w + f.x + u1 * f.w) / 2 - total / 2
        for (i, n) in names.enumerated() {
            let rect = CGRect(x: x, y: yc - pillH / 2, width: widths[i], height: pillH)
            let rr = Path(roundedRect: rect, cornerRadius: pillH / 2)
            ctx.fill(rr, with: .linearGradient(Gradient(colors: [deepGlass1, deepGlass2]),
                                               startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                               endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
            ctx.stroke(rr, with: .linearGradient(Gradient(colors: [brightGold.opacity(0.9), gold.opacity(0.3)]),
                                                 startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                 endPoint: CGPoint(x: rect.midX, y: rect.maxY)),
                       lineWidth: max(1, pillH * 0.05))
            emboss(ctx, n, CGPoint(x: rect.midX, y: rect.midY), fontSize, .semibold)
            x += widths[i] + gap
        }
    }
}

// MARK: - Snapshot
@MainActor
private func snapshot(to path: String, width: CGFloat, height: CGFloat, fill: Bool) {
    let view = WallpaperView(fill: fill).frame(width: width, height: height)
    let renderer = ImageRenderer(content: view); renderer.scale = 1
    guard let nsImage = renderer.nsImage, let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("snapshot failed\n".data(using: .utf8)!); exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path)); print("wrote \(path)")
}

// MARK: - App delegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var gates: [(window: NSWindow, gate: RenderGate)] = []
    var screenLocked = false
    var screensAsleep = false
    private let smokeRequested = ProcessInfo.processInfo.environment["BLW_SMOKE"] == "1" ||
        CommandLine.arguments.contains("--smoke")

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory); rebuild()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(recomputePause),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenDidLock), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenDidUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        wnc.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        if smokeRequested {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.printSmokeAndQuit()
            }
        }
    }
    @objc func screenDidLock() { screenLocked = true; recomputePause() }
    @objc func screenDidUnlock() { screenLocked = false; recomputePause() }
    @objc func screensDidSleep() { screensAsleep = true; recomputePause() }
    @objc func screensDidWake() { screensAsleep = false; recomputePause() }

    // A gate pauses its window's TimelineView when nothing of it can be seen.
    @objc func recomputePause() {
        let globallyDark = screenLocked || screensAsleep
        for (w, g) in gates {
            let paused = globallyDark || !w.occlusionState.contains(.visible)
            if g.paused != paused { g.paused = paused }
        }
    }
    @objc func rebuild() {
        windows.forEach { $0.orderOut(nil) }; windows.removeAll(); gates.removeAll()
        for screen in NSScreen.screens {
            let useFill = screen.frame.width / max(screen.frame.height, 1) > imgAspect
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            w.ignoresMouseEvents = true; w.isOpaque = true; w.backgroundColor = .black; w.hasShadow = false
            w.setFrame(screen.frame, display: true)
            let gate = RenderGate()
            let host = NSHostingView(rootView: WallpaperView(fill: useFill, gate: gate))
            host.frame = NSRect(origin: .zero, size: screen.frame.size); host.autoresizingMask = [.width, .height]
            w.contentView = host; w.orderFrontRegardless(); windows.append(w); gates.append((w, gate))
        }
        recomputePause()
    }

    private func printSmokeAndQuit() {
        let visible = windows.filter(\.isVisible)
        let frames = windows.map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.minX)),\(Int($0.frame.minY))" }.joined(separator: ",")
        let paused = gates.filter { $0.gate.paused }.count
        let loaded = baseImage != nil
        let line = "BLW_SMOKE|screens=\(NSScreen.screens.count)|windows=\(windows.count)|visible=\(visible.count)|paused=\(paused)|image_loaded=\(loaded)|frames=\(frames)"
        if let data = (line + "\n").data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
        NSApp.terminate(nil)
    }
}

// MARK: - Entry
let args = CommandLine.arguments
if let idx = args.firstIndex(of: "--snapshot"), idx + 1 < args.count {
    let path = args[idx + 1]
    let wv = idx + 3 < args.count ? CGFloat(Double(args[idx + 2]) ?? 1728) : 1728
    let hv = idx + 3 < args.count ? CGFloat(Double(args[idx + 3]) ?? 1117) : 1117
    let fill = args.contains("--fill")
    if let ai = args.firstIndex(of: "--at"), ai + 1 < args.count { forcedTime = Double(args[ai + 1]) }
    MainActor.assumeIsolated { snapshot(to: path, width: wv, height: hv, fill: fill) }
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate
app.run()
