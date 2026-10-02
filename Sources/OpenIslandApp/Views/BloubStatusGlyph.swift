// Native adaptation of bloub's idle / thinking / notify states.
// Copyright (c) 2026 Jérémy Perret. MIT; see docs/licenses/bloub-MIT.txt.
import AppKit
import SwiftUI

enum BloubTint: String, CaseIterable {
    case paper, approval, answer, blue, mint

    var color: NSColor {
        let rgb: (Double, Double, Double) = switch self {
        case .paper: (241, 234, 217)
        // Match IslandDesignPalette.Status's existing approval / answer colors.
        case .approval: (244, 164, 164)
        case .answer: (255, 213, 138)
        case .blue: (110, 167, 255)
        case .mint: (111, 185, 130)
        }
        return NSColor(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
    }
}

enum BloubWaitingMotion: String, CaseIterable {
    case still, badge, alive

    var title: String {
        switch self {
        case .still: "静态"
        case .badge: "通知点呼吸"
        case .alive: "呼吸＋眨眼＋微眼神"
        }
    }
}

struct BloubStatusGlyph: View {
    var mode: UnifiedBars.Mode
    var size: CGFloat = 24
    var isActive = true
    var tint: BloubTint = .paper
    var waitingMotion: BloubWaitingMotion = .still
    var backdrop: NSColor = .black
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LayerRepresentable(mode: mode, isActive: isActive, reduceMotion: reduceMotion,
                           tint: tint, waitingMotion: waitingMotion, backdrop: backdrop)
            .frame(width: size, height: size)
            .accessibilityHidden(true) // The surrounding surface supplies the task status.
    }

    private struct LayerRepresentable: NSViewRepresentable {
        let mode: UnifiedBars.Mode
        let isActive: Bool
        let reduceMotion: Bool
        let tint: BloubTint
        let waitingMotion: BloubWaitingMotion
        let backdrop: NSColor

        func makeNSView(context: Context) -> BloubLayerView {
            let view = BloubLayerView()
            view.update(mode: mode, isActive: isActive, reduceMotion: reduceMotion,
                        tint: tint, waitingMotion: waitingMotion, backdrop: backdrop)
            return view
        }

        func updateNSView(_ view: BloubLayerView, context: Context) {
            view.update(mode: mode, isActive: isActive, reduceMotion: reduceMotion,
                        tint: tint, waitingMotion: waitingMotion, backdrop: backdrop)
        }

        static func dismantleNSView(_ view: BloubLayerView, coordinator: ()) {
            view.tearDown()
        }
    }
}

/// Only generates paths when geometry/state/visibility changes. Core Animation
/// plays the sampled paths; there is no frame timer or SwiftUI TimelineView.
final class BloubLayerView: NSView {
    private let bodyLayer = CAShapeLayer()
    private let bodyClip = CAShapeLayer()
    private let dotLayers = [CAShapeLayer(), CAShapeLayer()]
    private let notificationLayer = CAShapeLayer()
    private let eyeContainer = CALayer()
    private let eyeLayers = [CAShapeLayer(), CAShapeLayer()]
    private let eyeClip = CAShapeLayer()
    private let badgeCutout = CAShapeLayer()
    private var mode: UnifiedBars.Mode = .idle
    private var isActive = true
    private var reduceMotion = false
    private var tint: BloubTint = .paper
    private var waitingMotion: BloubWaitingMotion = .still
    private var backdrop: NSColor = .black
    private var lastConfiguration: Configuration?
    private var windowObserver: NSObjectProtocol?
    private var notificationCleanup: DispatchWorkItem?
    private(set) var animationGeneration = 0

    private struct Configuration: Equatable {
        let mode: UnifiedBars.Mode
        let size: CGSize
        let animates: Bool
        let scale: CGFloat
        let tint: BloubTint
        let waitingMotion: BloubWaitingMotion
        let backdrop: NSColor
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true
        bodyClip.fillColor = NSColor.white.cgColor
        bodyLayer.mask = bodyClip
        eyeClip.fillColor = NSColor.white.cgColor
        eyeContainer.mask = eyeClip
        eyeLayers.forEach { eyeContainer.addSublayer($0) }
        let paper = NSColor(red: 241 / 255, green: 234 / 255, blue: 217 / 255, alpha: 1).cgColor
        bodyLayer.fillColor = paper
        dotLayers.forEach { $0.fillColor = paper }
        notificationLayer.fillColor = NSColor(red: 36 / 255, green: 150 / 255, blue: 232 / 255, alpha: 1).cgColor
        for child in [bodyLayer] + dotLayers + [eyeContainer, badgeCutout, notificationLayer] {
            layer?.addSublayer(child)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(mode: UnifiedBars.Mode, isActive: Bool, reduceMotion: Bool,
                tint: BloubTint = .paper, waitingMotion: BloubWaitingMotion = .still,
                backdrop: NSColor = .black) {
        guard self.mode != mode || self.isActive != isActive || self.reduceMotion != reduceMotion
                || self.tint != tint || self.waitingMotion != waitingMotion || self.backdrop != backdrop
                || lastConfiguration == nil else { return }
        self.mode = mode
        self.isActive = isActive
        self.reduceMotion = reduceMotion
        self.tint = tint
        self.waitingMotion = waitingMotion
        self.backdrop = backdrop
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        if let window {
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowVisibilityChanged() }
            }
        } else {
            stopAnimations()
        }
        needsLayout = true
    }

    override func viewDidHide() {
        super.viewDidHide()
        stopAnimations()
        needsLayout = true
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    // Each animated path contains one shape. In particular the eyes never share
    // an even-odd compound path with the badge cutout: CA's intermediate
    // compound-path tessellation could draw a flashing wedge between them.
    private var renderedLayers: [CAShapeLayer] {
        [bodyLayer, bodyClip] + dotLayers + [notificationLayer] + eyeLayers + [badgeCutout, eyeClip]
    }

    private func windowVisibilityChanged() {
        if window?.isVisible != true || window?.occlusionState.contains(.visible) != true {
            stopAnimations() // Hidden windows may not get another layout pass.
        }
        needsLayout = true
    }

    var hasScheduledAnimations: Bool { renderedLayers.contains { !($0.animationKeys() ?? []).isEmpty } }

    func stopAnimations() {
        notificationCleanup?.cancel()
        notificationCleanup = nil
        renderedLayers.forEach { $0.removeAllAnimations() }
        lastConfiguration = nil
    }

    func tearDown() {
        stopAnimations()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { stopAnimations(); return }
        let visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
            && !isHiddenOrHasHiddenAncestor
        let configuration = Configuration(
            mode: mode, size: bounds.size, animates: isActive && visible && !reduceMotion,
            scale: window?.backingScaleFactor ?? 2, tint: tint, waitingMotion: waitingMotion, backdrop: backdrop
        )
        guard configuration != lastConfiguration else { return }
        let previous = lastConfiguration
        // Presentation paths preserve continuity even if another state arrives mid-morph.
        let origins = renderedLayers.map { $0.presentation()?.path ?? $0.path }
        let opacities = renderedLayers.map { $0.presentation()?.opacity ?? $0.opacity }
        stopAnimations()
        lastConfiguration = configuration
        animationGeneration += 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bodyLayer.fillColor = tint.color.cgColor
        eyeContainer.frame = bounds
        eyeLayers.forEach { $0.fillColor = backdrop.cgColor }
        badgeCutout.fillColor = backdrop.cgColor
        dotLayers.forEach { $0.fillColor = tint.color.cgColor }
        for child in renderedLayers {
            child.frame = CGRect(origin: .zero, size: bounds.size)
            child.contentsScale = configuration.scale
        }
        let settled = BloubGeometry.frame(mode: mode, time: 0)
        let target = settled.paths(in: bounds.size)
        for (index, child) in renderedLayers.enumerated() {
            child.path = target[index]
            child.opacity = settled.opacities[index]
        }
        CATransaction.commit()

        guard configuration.animates else { return }
        let now = CACurrentMediaTime()
        let morphs = previous?.animates == true && previous?.size == configuration.size && previous?.mode != mode
        let duration = morphs ? 0.45 : 0
        if morphs {
            for (index, child) in renderedLayers.enumerated() {
                if let origin = origins[index] {
                    let animation = CABasicAnimation(keyPath: "path")
                    animation.fromValue = origin
                    animation.toValue = target[index]
                    animation.duration = duration
                    animation.beginTime = now
                    animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                    child.add(animation, forKey: "state-morph")
                }
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = opacities[index]
                fade.toValue = settled.opacities[index]
                fade.duration = duration
                fade.beginTime = now
                child.add(fade, forKey: "state-opacity")
            }
        }

        if mode == .waiting && previous?.mode != .waiting {
            // Pop once on entry; changing tint or motion does not replay it.
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.01, 1.14, 1]
            pop.keyTimes = [0, 0.65, 1]
            pop.duration = 0.45
            pop.beginTime = now
            // Scale about the badge itself, not the center of the whole glyph.
            let position = settled.notification.center(in: bounds.size)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            notificationLayer.anchorPoint = CGPoint(x: position.x / bounds.width, y: position.y / bounds.height)
            notificationLayer.position = position
            CATransaction.commit()
            notificationLayer.add(pop, forKey: "notification-entry")
            // A hidden/offscreen layer may retain an expired CA animation key.
            // Settle explicitly once; this is not a repeating rendering clock.
            let generation = animationGeneration
            let cleanup = DispatchWorkItem { [weak self] in
                guard let self, self.animationGeneration == generation else { return }
                self.notificationLayer.removeAnimation(forKey: "notification-entry")
                self.notificationCleanup = nil
            }
            notificationCleanup = cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: cleanup)
        }
        if mode == .waiting && waitingMotion == .still { return }

        let period = BloubGeometry.loopPeriod(for: mode)
        let count = Int(period * 20)
        let frames = (0...count).map {
            BloubGeometry.frame(mode: mode, time: Double($0) * period / Double(count), waitingMotion: waitingMotion)
        }
        let paths = frames.map { $0.paths(in: bounds.size) }
        for (index, child) in renderedLayers.enumerated() {
            // Only animate features that move in this state; the eyes and
            // notification remain independent throughout the whole loop.
            let animatedIndices: Set<Int> = switch mode {
            case .idle: [5, 6]
            case .running: [0, 1, 2, 3]
            case .waiting: waitingMotion == .badge ? [4, 7] : [4, 5, 6, 7]
            }
            guard animatedIndices.contains(index) else { continue }
            let path = CAKeyframeAnimation(keyPath: "path")
            if mode == .waiting && (index == 5 || index == 6) {
                // Use the already projected eye shapes directly. A nearly
                // circular rounded rectangle has tiny straight edges; avoid
                // CA interpolating those into transient spikes during a blink.
                path.values = paths.dropLast().map { $0[index] }
                path.keyTimes = (0...count).map { NSNumber(value: Double($0) / Double(count)) }
                path.calculationMode = .discrete
            } else {
                path.values = paths.map { $0[index] }
            }
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = frames.map { NSNumber(value: $0.opacities[index]) }
            let group = CAAnimationGroup()
            group.animations = [path, opacity]
            path.duration = period
            opacity.duration = period
            group.duration = period
            group.beginTime = now + duration
            group.repeatCount = .infinity
            child.add(group, forKey: "state-loop")
        }
    }
}

/// A small clock-free port of the measured geometry in bloub/face.ts,
/// states.ts and decor.ts. Idle uses 12 s; the optional waiting loop uses 25 s.
enum BloubGeometry {
    static let calmPeriod = 25.0
    static let waitingBlinkPeriod = 5.0
    static let blinkDuration = 0.7

    static func loopPeriod(for mode: UnifiedBars.Mode) -> TimeInterval {
        switch mode {
        case .running: 1.5
        case .idle: 12
        case .waiting: calmPeriod
        }
    }

    private static func blinkLid(time: Double) -> Double {
        let clock = time.truncatingRemainder(dividingBy: waitingBlinkPeriod)
        let progress = (clock - 3.4) / blinkDuration
        guard progress >= 0 && progress <= 1 else { return 1 }
        return (1 + cos(progress * .pi * 2)) / 2
    }
    struct Dot {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var radius: CGFloat = 0.0001
        var opacity: Float = 0

        func center(in size: CGSize) -> CGPoint {
            let radius = min(size.width, size.height) / 2.4
            return CGPoint(x: size.width / 2 + x * radius, y: size.height / 2 + y * radius)
        }

        func path(in size: CGSize) -> CGPath {
            let center = center(in: size)
            let r = radius * min(size.width, size.height) / 2.4
            return CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2), transform: nil)
        }
    }

    struct Frame {
        var body = Dot(radius: 1, opacity: 1)
        var eyes: [CGPath] = []
        var sideDots = [Dot(), Dot()]
        var notification = Dot(x: cos(-42 * .pi / 180) * 1.003, y: sin(-42 * .pi / 180) * 1.003)

        var eyeOpacity: Float = 1
        var opacities: [Float] {
            [1, 1, sideDots[0].opacity, sideDots[1].opacity, notification.opacity,
             eyeOpacity, eyeOpacity, notification.opacity, 1]
        }

        func paths(in size: CGSize) -> [CGPath] {
            let r = min(size.width, size.height) / 2.4
            var transform = CGAffineTransform(a: r, b: 0, c: 0, d: r, tx: size.width / 2, ty: size.height / 2)
            let outline = BloubGeometry.circlePath(x: body.x, y: body.y, radius: body.radius)
            let notchRadius = notification.opacity > 0 ? notification.radius + 0.054 : 0.0001
            let cutout = Dot(x: notification.x, y: notification.y, radius: notchRadius, opacity: notification.opacity)
            let projectedOutline = outline.copy(using: &transform)!
            return [projectedOutline, projectedOutline,
                    sideDots[0].path(in: size), sideDots[1].path(in: size), notification.path(in: size),
                    eyes[0].copy(using: &transform)!, eyes[1].copy(using: &transform)!,
                    cutout.path(in: size), projectedOutline]
        }
    }

    static func frame(mode: UnifiedBars.Mode, time: Double, waitingMotion: BloubWaitingMotion = .still) -> Frame {
        var frame = Frame()
        var gaze = (yaw: 28.49, pitch: 28.62, roll: -13.0)
        var split = 15.46
        var eyeWidth = 0.186
        var eyeHeight = 0.412
        var lid = 1.0
        if mode == .running {
            frame.body.x = -0.013
            frame.body.radius = dotRadius(time: time, index: 1)
            frame.sideDots = [0, 2].map { index in
                Dot(x: index == 0 ? -0.557 : 0.532, radius: dotRadius(time: time, index: index),
                    opacity: Float(0.55 + 0.45 * dotPulse(time: time, index: index)))
            }
            eyeWidth = 0.0001
            eyeHeight = 0.0001
            frame.eyeOpacity = 0
        } else if mode == .waiting {
            gaze = (-21.94, -5.82, -12.2)
            split = 18.89
            eyeWidth = 0.505
            eyeHeight = 0.498
            frame.notification.radius = 0.15
            frame.notification.opacity = 1
            if waitingMotion != .still {
                let breath = (1 - cos(time / 5 * .pi * 2)) / 2
                frame.notification.radius *= 1 + 0.08 * breath
            }
            if waitingMotion == .alive {
                let phase = time / calmPeriod * .pi * 2
                gaze.yaw += sin(phase) * 2.5
                gaze.pitch += sin(phase * 2) * 1.5
                lid = blinkLid(time: time)
            }
        } else {
            let phase = time / 12 * .pi * 2
            gaze.yaw += sin(phase) * 4 + sin(phase * 3) * 1.2
            gaze.pitch += sin(phase * 2) * 3
            gaze.roll += sin(phase) * 1.4
            let clock = time.truncatingRemainder(dividingBy: 12)
            for start in [1.4, 5.5, 9.4] {
                let k = (clock - start) / 0.18
                if k >= 0 && k <= 1 { lid = k < 0.45 ? 1 - k / 0.45 : (k - 0.45) / 0.55 }
            }
        }
        frame.eyes = eyePaths(gaze: gaze, split: split, width: eyeWidth, height: eyeHeight, lid: lid)
        return frame
    }

    static func dotPulse(time: Double, index: Int) -> Double {
        let raw = (time - Double(index) * 0.5) / 1.5
        let phase = raw - floor(raw)
        return phase < 0.5 ? min(1, 1 - cos(phase * .pi * 2)) : 0
    }

    private static func dotRadius(time: Double, index: Int) -> CGFloat {
        0.165 * (1 + 0.25 * dotPulse(time: time, index: index))
    }

    /// Same 64 cubic segments in every mode, so interrupted CA path morphs
    /// can use the current presentation path without changing topology.
    private static func circlePath(x: CGFloat, y: CGFloat, radius: CGFloat) -> CGPath {
        let points = (0..<64).map { index -> CGPoint in
            let angle = CGFloat(index) / 64 * .pi * 2
            return CGPoint(x: x + cos(angle) * radius, y: y + sin(angle) * radius)
        }
        let path = CGMutablePath()
        path.move(to: points[0])
        for index in 0..<64 {
            let p0 = points[(index + 63) % 64], p1 = points[index]
            let p2 = points[(index + 1) % 64], p3 = points[(index + 2) % 64]
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }

    private static func eyePaths(gaze: (yaw: Double, pitch: Double, roll: Double), split: Double,
                                 width: CGFloat, height: CGFloat, lid: Double) -> [CGPath] {
        typealias Vector = (x: Double, y: Double, z: Double)
        func spin(_ u: Vector, _ v: Vector, _ degrees: Double) -> (Vector, Vector) {
            let c = cos(degrees * .pi / 180), s = sin(degrees * .pi / 180)
            return ((u.x * c + v.x * s, u.y * c + v.y * s, u.z * c + v.z * s),
                    (v.x * c - u.x * s, v.y * c - u.y * s, v.z * c - u.z * s))
        }
        var forward: Vector = (0, 0, 1), right: Vector = (1, 0, 0), down: Vector = (0, 1, 0)
        (forward, right) = spin(forward, right, gaze.yaw)
        (down, forward) = spin(down, forward, gaze.pitch)
        (right, down) = spin(right, down, gaze.roll)
        return [-1.0, 1.0].map { side in
            let (eye, tangent) = spin(forward, right, split * side)
            let k = 0.06 + 0.94 * lid
            var matrix = CGAffineTransform(a: tangent.x, b: tangent.y * k, c: down.x, d: down.y * k,
                                           tx: eye.x, ty: eye.y)
            let r = min(width, height) / 2
            let path = CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                              cornerWidth: r, cornerHeight: r, transform: nil)
            return path.copy(using: &matrix)!
        }
    }
}
