import AppKit
import OpenIslandCore

/// Native port of approved R9 visuals, with the original shell and task paths.
/// Bloub sprites are exported from the actual website engine/SVG painter. All task
/// pixels are recorded demo sessions, never live source acceptance evidence.
@MainActor
final class OnboardingSceneView: NSView {
    let media: OnboardingMedia
    let language: OnboardingLanguage
    var geometry: OnboardingGeometry
    var time: Double = 0
    var reduceMotion = false
    private var brandLabels: [NSAttributedString] = []
    override var isFlipped: Bool { true }

    init(media: OnboardingMedia, language: OnboardingLanguage, geometry: OnboardingGeometry) {
        self.media = media; self.language = language; self.geometry = geometry
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(language == .chinese ? "AIsland 欢迎介绍，示例任务演示" : "AIsland welcome, demo task scenes")
        brandLabels = ["f7f5ee", "24354f"].map {
            NSAttributedString(string: "AIsland", attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor(cgColor: color($0))!
            ])
        }
        // Cold AppKit font layout/rasterization took ~36ms in the isolated
        // first-render probe. Prime only this small label before the score;
        // never render full scenes or retain full-screen warmup textures.
        if let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
           let context = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            for label in brandLabels { label.draw(at: .zero) }
            context.cgContext.flush()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private func smooth(_ x: Double) -> Double { let x = clamp(x); return x * x * (3 - 2 * x) }
    private func ease(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return CGColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: alpha)
    }
    private func mix(_ a: String, _ b: String, _ t: Double) -> CGColor {
        let aa = color(a).components!, bb = color(b).components!
        return CGColor(red: lerp(aa[0], bb[0], t), green: lerp(aa[1], bb[1], t), blue: lerp(aa[2], bb[2], t), alpha: 1)
    }
    private func rect(_ c: CGContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double, _ fill: CGColor) {
        c.setFillColor(fill); c.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)); c.fillPath()
    }
    private func dot(_ c: CGContext, _ x: Double, _ y: Double, _ r: Double, _ fill: CGColor) {
        c.setFillColor(fill); c.fillEllipse(in: CGRect(x: x-r, y: y-r, width: r*2, height: r*2))
    }
    private func image(_ c: CGContext, _ image: CGImage, _ rect: CGRect) {
        c.saveGState(); c.translateBy(x: rect.minX, y: rect.maxY); c.scaleBy(x: 1, y: -1)
        c.draw(image, in: CGRect(origin: .zero, size: rect.size)); c.restoreGState()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height, t = time, motion = !reduceMotion
        background(c, w, h, t, motion)
        let s = min(w / (w < 640 ? 780 : 1040), h / 720)
        let cx = w * 0.5, cy = h * lerp(0.37, 0.43, motion ? smooth((t-2.4)/0.8) : (t >= 3 ? 1 : 0))
        let awaken = motion ? ease((t-0.4)/0.95) : (t >= 0.4 ? 1.0 : 0.0)
        let collapse = motion ? smooth((t-18.1)/2.6) : (t >= 18.1 ? 1.0 : 0.0)
        let targetW = geometry.width, targetH = geometry.height
        let x = lerp(cx, geometry.centerX, collapse), y = lerp(cy, targetH/2, collapse)
        let gather = smooth((t-3)/0.4)
        let iw = lerp(lerp(20, 282*s, awaken)*(1-gather*0.23), targetW, collapse)
        let ih = lerp(lerp(20, 83*s, awaken)*(1-gather*0.16), targetH, collapse)
        logos(c, t, cx, cy, s, motion)
        rows(c, t, cx, cy, s, motion)
        let hasPanel = nativePanel(c, t, w, h, s, motion)
        if t >= 18.1 {
            closed(c, x, y, lerp(277*s, targetW, collapse), lerp(32*s, targetH, collapse), t, motion)
        } else if !hasPanel {
            island(c, x, y, iw, ih, t, s)
        }
        if let glyph = OnboardingBrandGeometry.gather(time: t,
            island: CGRect(x: x-iw/2, y: y-ih/2, width: iw, height: ih), reduceMotion: reduceMotion) {
            brandCharacter(c, glyph)
        }
        if let orbit = OnboardingBrandGeometry.orbit(time: t, bounds: bounds.size, reduceMotion: reduceMotion) {
            brandCharacter(c, orbit)
        }
        if t >= 1.35 && t < 2.45 && motion {
            let elapsed = (t-1.35)/1.1
            c.saveGState(); c.setAlpha((1-elapsed)*0.32); c.setStrokeColor(color("bfd8ff")); c.setLineWidth(0.9)
            let rx = iw*0.6+elapsed*75*s, ry = ih*0.64+elapsed*28*s
            c.strokeEllipse(in: CGRect(x: x-rx, y: y-ry, width: rx*2, height: ry*2)); c.restoreGState()
        }
        let lightBackground = t >= 5.3 && t < 8.2 || t >= 13.2
        brandLabels[lightBackground ? 1 : 0].draw(at: CGPoint(x: 30, y: max(40, window?.screen?.safeAreaInsets.top ?? 0) + 12))
    }

    private func brandCharacter(_ c: CGContext, _ sprite: OnboardingBrandGeometry.Sprite) {
        guard let frame = media.brand.image(state: sprite.state, sampleTime: sprite.sampleTime,
                                            reduceMotion: reduceMotion) else { return }
        c.saveGState(); c.setAlpha(sprite.opacity)
        image(c, frame, sprite.rect)
        c.restoreGState()
    }

    private func background(_ c: CGContext, _ w: Double, _ h: Double, _ t: Double, _ motion: Bool) {
        let palettes: [(Double, String, String, String)] = [
            (0,"030711","091638","2050c4"), (1.35,"071d53","123987","487ffa"),
            (5.3,"eef2fd","c8d7f5","f9f7f0"), (8.2,"1a1728","382b42","65465f"),
            (10.7,"191d28","35322d","706346"), (13.2,"e7edf9","c1d3f3","f7f6f0"),
            (15.7,"eaf1ef","cededc","f7f6f0"), (18.1,"f0f2f8","dadfe9","eef0f8")]
        let index = palettes.lastIndex(where: { $0.0 <= t }) ?? 0
        let current = palettes[index], previous = palettes[max(0,index-1)]
        let fade = motion ? smooth((t-current.0)/1.25) : 1
        let top = mix(previous.1,current.1,fade), bottom = mix(previous.2,current.2,fade)
        c.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top,bottom] as CFArray, locations: [0,1])!, start: .zero, end: CGPoint(x: w*0.16,y: h), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
        let glow = mix(previous.3,current.3,fade)
        c.saveGState(); c.setAlpha(0.45)
        c.drawRadialGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [glow,glow.copy(alpha: 0)!] as CFArray, locations: [0,1])!, startCenter: CGPoint(x: w*(0.63+(motion ? sin(t*0.12)*0.06 : 0)),y: h*(0.34+(motion ? cos(t*0.18)*0.06 : 0))), startRadius: 0, endCenter: CGPoint(x: w*(0.63+(motion ? sin(t*0.12)*0.06 : 0)),y: h*(0.34+(motion ? cos(t*0.18)*0.06 : 0))), endRadius: w*0.65, options: [.drawsAfterEndLocation]); c.restoreGState()
        if t < 5.3 {
            let opening = motion ? ease((t-0.4)/2.2) : 1
            c.saveGState(); c.translateBy(x: w*0.5,y: h*0.36); c.rotate(by: -0.28)
            c.setAlpha(opening*0.15)
            c.saveGState(); c.clip(to: CGRect(x: -w,y: -h*0.12,width: w*2,height: h*0.17))
            let blue = color("91b4ff")
            c.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [blue.copy(alpha: 0)!,blue,blue.copy(alpha: 0)!] as CFArray, locations: [0,0.5,1])!, start: CGPoint(x: -w*0.7,y: 0), end: CGPoint(x: w*0.7,y: 0), options: []); c.restoreGState()
            c.setAlpha(opening*0.12); c.setFillColor(color("91b4ff")); c.fill(CGRect(x: -w,y: h*0.11,width: w*2,height: 1)); c.restoreGState()
            c.saveGState(); c.translateBy(x: w*0.5,y: h*0.36); c.scaleBy(x: 1,y: 0.45)
            for i in 0..<5 {
                let radius = (w*0.13+Double(i)*w*0.056)*(0.35+opening*0.9)
                c.setAlpha(opening*(0.17-Double(i)*0.025)); c.setStrokeColor(color("adc9ff")); c.setLineWidth(i == 0 ? 1.5 : 0.6)
                c.strokeEllipse(in: CGRect(x: -radius,y: -radius,width: radius*2,height: radius*2))
            }; c.restoreGState()
        } else if t < 8.2 || t >= 13.2 {
            c.saveGState(); c.setAlpha(0.16); c.translateBy(x: w*0.88,y: h*0.47); c.rotate(by: -0.5)
            c.setFillColor(color("7f9cca")); c.fill(CGRect(x: -w*0.08,y: -h,width: w*0.17,height: h*2))
            c.setFillColor(color("ffffff")); c.fill(CGRect(x: -w*0.22,y: -h,width: w*0.12,height: h*2)); c.restoreGState()
            if t >= 18.1 {
                c.saveGState(); c.setAlpha(smooth((t-18.1)/1.1)*0.2)
                rect(c,w*0.13,h*0.3,w*0.74,h*0.55,16,color("ffffff",0.38)); c.restoreGState()
            }
        } else {
            c.saveGState(); c.setAlpha(0.18)
            for i in 0..<35 { dot(c, (Double(i)*137.5).truncatingRemainder(dividingBy: 997)/997*w, (Double(i)*213.2).truncatingRemainder(dividingBy: 631)/631*h, 0.7,color("b4c8e4")) }
            c.restoreGState()
        }
        c.saveGState(); c.setAlpha(0.023); c.setFillColor(color("ffffff"))
        for i in 0..<500 { c.fill(CGRect(x: (Double(i)*73.13).truncatingRemainder(dividingBy: 997)/997*w,y: (Double(i)*39.71).truncatingRemainder(dividingBy: 631)/631*h,width: 1,height: 1)) }
        c.restoreGState()
    }

    private func logos(_ c: CGContext, _ t: Double, _ x: Double, _ y: Double, _ s: Double, _ motion: Bool) {
        guard t >= 3 && t < 5.3 else { return }
        let coords: [(Double,Double)] = [(-190,-65),(-98,-120),(4,-143),(111,-113),(195,-48),(177,52),(83,95),(-38,100),(-148,53)]
        for (i, logo) in media.logos.enumerated() {
            let local = t-3-Double(i)*0.045
            let enter = motion ? smooth(local/0.35) : 1, jump = motion ? smooth((local-0.83)/0.74) : 0
            let out = motion ? 1-smooth((local-1.44)/0.18) : 1
            let (dx,dy) = coords[i], size = (37-jump*20)*s
            c.saveGState(); c.setAlpha(enter*out); c.translateBy(x: x+dx*s*(1-jump),y: y+dy*s*(1-jump)-(motion ? sin(jump*Double.pi)*32*s : 0)); c.rotate(by: motion ? (1-jump)*dx*0.00022 : 0)
            rect(c,-size*0.5,-size*0.5,size,size,size*0.23,color("f7f8fc"))
            image(c,logo,CGRect(x: -size*0.45,y: -size*0.45,width: size*0.9,height: size*0.9)); c.restoreGState()
        }
    }

    private func rows(_ c: CGContext, _ t: Double, _ x: Double, _ y: Double, _ s: Double, _ motion: Bool) {
        guard t >= 5.3 && t < 8.2 else { return }
        for (i, row) in media.rows.enumerated() {
            let enter = motion ? ease((t-5.3-Double(i)*0.09)/0.45) : 1
            let travel = motion ? smooth((t-7.24-Double(i)*0.075)/0.62) : 0
            let exit = motion ? 1-smooth((travel-0.46)/0.54) : 1
            let side = i % 2 == 0 ? -1.0 : 1.0, dy = (i < 2 ? -53.0 : 53.0)*s
            let xx = x+side*(258+(1-enter)*72)*s*(1-travel), yy = y+dy*(1-travel)+(1-enter)*18*s
            if motion && travel < 0.85 {
                c.saveGState(); c.setAlpha(enter*(1-travel)*0.32); c.beginPath(); c.move(to: CGPoint(x: x+side*110*s,y: y))
                c.addCurve(to: CGPoint(x: xx,y: y+dy), control1: CGPoint(x: x+side*150*s,y: y),control2: CGPoint(x: x+side*160*s,y: y+dy))
                c.setStrokeColor(color(["d58b68","6fa2e5","92bb95","a092c8"][i])); c.setLineWidth(1.15*s); c.strokePath(); c.restoreGState()
            }
            let width = (190-travel*130)*s, height = width*Double(row.height)/Double(row.width)
            c.saveGState(); c.setAlpha(enter*exit); c.translateBy(x: xx,y: yy); c.rotate(by: side*0.02*(1-travel))
            c.setShadow(offset: CGSize(width: 0,height: -9),blur: 17,color: color("142d66",0.2))
            rect(c,-width/2,-height/2,width,height,10,color("0c0c0e")); c.setShadow(offset: .zero,blur: 0,color: nil)
            c.addPath(CGPath(roundedRect: CGRect(x: -width/2,y: -height/2,width: width,height: height),cornerWidth: 10,cornerHeight: 10,transform: nil)); c.clip()
            image(c,row,CGRect(x: -width/2,y: -height/2,width: width,height: height)); c.restoreGState()
        }
    }

    private func nativePanel(_ c: CGContext, _ t: Double, _ w: Double, _ h: Double, _ s: Double, _ motion: Bool) -> Bool {
        guard let scene = OnboardingTimeline.scene(at: t), let clip = media.clips[scene.key] else { return false }
        let enter = motion ? ease((t-scene.start)/0.16) : 1
        let frame = motion ? clip.frames[OnboardingTimeline.frameIndex(time: t,start: scene.start,fps: clip.metadata.fps,frames: clip.frames.count)] : clip.still
        let width = min(560*s,w*0.78,h*0.65*Double(clip.metadata.width)/Double(clip.metadata.height))
        let height = width*Double(clip.metadata.height)/Double(clip.metadata.width)
        c.saveGState(); c.translateBy(x: w/2,y: h*0.2)
        c.clip(to: CGRect(x: -width/2-2,y: 0,width: width+4,height: height*enter))
        image(c,frame,CGRect(x: -width/2,y: 0,width: width,height: height)); c.restoreGState()
        return true
    }

    private func closed(_ c: CGContext, _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ t: Double, _ motion: Bool) {
        guard let clip = media.clips["closed"] else { return }
        let frame = motion ? clip.frames[OnboardingTimeline.frameIndex(time: t,start: 18.1,fps: clip.metadata.fps,frames: clip.frames.count,looping: true)] : clip.still
        image(c,frame,CGRect(x: x-width/2,y: y-height/2,width: width,height: height))
    }

    private func island(_ c: CGContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ t: Double, _ s: Double) {
        c.saveGState(); c.translateBy(x: x,y: y)
        c.setShadow(offset: CGSize(width: 0,height: -12*s),blur: 30*s,color: color(t < 5.3 ? "000000" : "071630",t < 5.3 ? 0.8 : 0.31))
        let r = h*0.44, p = CGMutablePath()
        p.move(to: CGPoint(x: -w/2,y: -h/2)); p.addLine(to: CGPoint(x: w/2,y: -h/2)); p.addLine(to: CGPoint(x: w/2,y: h/2-r))
        p.addQuadCurve(to: CGPoint(x: w/2-r,y: h/2),control: CGPoint(x: w/2,y: h/2)); p.addLine(to: CGPoint(x: -w/2+r,y: h/2))
        p.addQuadCurve(to: CGPoint(x: -w/2,y: h/2-r),control: CGPoint(x: -w/2,y: h/2)); p.closeSubpath()
        c.addPath(p); c.setFillColor(color("04070d")); c.fillPath(); c.setShadow(offset: .zero,blur: 0,color: nil)
        for direction in [-1.0,1.0] { rect(c,direction*h*0.13-h*0.075/2,-h*0.3/2,h*0.075,h*0.3,h*0.075/2,color("f2ead8")) }
        dot(c,w*0.27,-h*0.11,max(2,3*s),color("6ea7ff"))
        c.setStrokeColor(color("ffffff",0.055)); c.setLineWidth(1); c.move(to: CGPoint(x: -w*0.36,y: -h/2+1)); c.addLine(to: CGPoint(x: w*0.36,y: -h/2+1)); c.strokePath(); c.restoreGState()
    }

}
