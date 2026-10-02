import AppKit
import Testing
@testable import OpenIslandApp

struct BloubStatusGlyphTests {
    @Test
    func allFramesFitTheRealGlyphSlot() {
        let modes: [UnifiedBars.Mode] = [.idle, .running, .waiting]
        for size in [CGSize(width: 24, height: 24), CGSize(width: 24, height: 32)] {
            let slot = CGRect(origin: .zero, size: size).insetBy(dx: -0.01, dy: -0.01)
            for mode in modes {
                for index in 0...240 {
                    let frame = BloubGeometry.frame(mode: mode, time: Double(index) / 20)
                    for path in frame.paths(in: size) {
                        let box = path.boundingBoxOfPath
                        #expect(box.minX.isFinite && box.minY.isFinite && box.maxX.isFinite && box.maxY.isFinite)
                        #expect(slot.contains(box))
                    }
                    #expect(frame.opacities.allSatisfy { $0 >= 0 && $0 <= 1 })
                }
            }
        }
    }

    @Test
    func everyStateHasTheSamePathTopologyForInterruptedMorphs() {
        func topology(_ path: CGPath) -> [CGPathElementType] {
            var elements: [CGPathElementType] = []
            path.applyWithBlock { elements.append($0.pointee.type) }
            return elements
        }
        let size = CGSize(width: 24, height: 24)
        let reference = BloubGeometry.frame(mode: .idle, time: 0).paths(in: size).map(topology)
        for mode in [UnifiedBars.Mode.idle, .running, .waiting] {
            for time in [0.0, 1.45, 1.5, 5.5, 11.99, 12] {
                let paths = BloubGeometry.frame(mode: mode, time: time).paths(in: size)
                #expect(paths.map(topology) == reference)
            }
        }
    }

    @Test
    func repeatingPathsHaveNoLoopBoundaryJump() {
        let size = CGSize(width: 24, height: 24)
        for mode in [UnifiedBars.Mode.idle, .running] {
            let period = BloubGeometry.loopPeriod(for: mode)
            let start = BloubGeometry.frame(mode: mode, time: 0)
            let end = BloubGeometry.frame(mode: mode, time: period)
            func points(_ path: CGPath) -> [CGPoint] {
                var points: [CGPoint] = []
                path.applyWithBlock { pointer in
                    let element = pointer.pointee
                    let count: Int
                    switch element.type {
                    case .moveToPoint, .addLineToPoint: count = 1
                    case .addQuadCurveToPoint: count = 2
                    case .addCurveToPoint: count = 3
                    case .closeSubpath: count = 0
                    @unknown default: count = 0
                    }
                    points.append(contentsOf: (0..<count).map { element.points[$0] })
                }
                return points
            }
            for (a, b) in zip(start.paths(in: size), end.paths(in: size)) {
                let p = points(a), q = points(b)
                #expect(p.count == q.count)
                #expect(zip(p, q).allSatisfy { abs($0.x - $1.x) < 0.00001 && abs($0.y - $1.y) < 0.00001 })
            }
            #expect(start.opacities == end.opacities)
        }
    }

    @Test
    func thinkingDotsPulseInOrderAndNotifyHolds() {
        for index in 0...2 {
            let peak = Double(index) * 0.5 + 0.375
            #expect(abs(BloubGeometry.dotPulse(time: peak, index: index) - 1) < 0.00001)
            #expect(BloubGeometry.dotPulse(time: peak + 0.75, index: index) == 0)
        }
        let waiting = BloubGeometry.frame(mode: .waiting, time: 1)
        #expect(waiting.notification.opacity == 1)
        #expect(waiting.notification.radius == 0.15)
        #expect(waiting.notification.path(in: CGSize(width: 24, height: 24))
                    == BloubGeometry.frame(mode: .waiting, time: 30).notification.path(in: CGSize(width: 24, height: 24)))
    }

    @MainActor
    @Test
    func detachedAndInactiveViewsDoNotScheduleAnimationsOrRestartOnUnchangedUpdates() {
        let view = BloubLayerView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        view.update(mode: .running, isActive: true, reduceMotion: false)
        view.layoutSubtreeIfNeeded()
        #expect(!view.hasScheduledAnimations) // Detached from any visible window.
        let generation = view.animationGeneration
        view.update(mode: .running, isActive: true, reduceMotion: false)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        #expect(view.animationGeneration == generation)
        view.update(mode: .waiting, isActive: false, reduceMotion: false)
        view.layoutSubtreeIfNeeded()
        #expect(!view.hasScheduledAnimations)
        view.update(mode: .idle, isActive: true, reduceMotion: true)
        view.layoutSubtreeIfNeeded()
        #expect(!view.hasScheduledAnimations)
    }

    @Test
    func animatedWaitingFitsItsSlotAndReturnsToTheSameFrame() {
        let size = CGSize(width: 24, height: 24)
        let slot = CGRect(origin: .zero, size: size).insetBy(dx: -0.01, dy: -0.01)
        for motion in [BloubWaitingMotion.badge, .alive] {
            for index in 0...500 {
                let frame = BloubGeometry.frame(mode: .waiting, time: Double(index) / 20, waitingMotion: motion)
                #expect(frame.paths(in: size).allSatisfy { slot.contains($0.boundingBoxOfPath) })
                #expect(frame.opacities.allSatisfy { $0 >= 0 && $0 <= 1 })
            }
            let a = BloubGeometry.frame(mode: .waiting, time: 0, waitingMotion: motion)
            let b = BloubGeometry.frame(mode: .waiting, time: 25, waitingMotion: motion)
            // Floating-point trig at 2π need not be bit-for-bit equal to zero.
            for (start, end) in zip(a.paths(in: size), b.paths(in: size)) {
                var first: [CGPoint] = [], last: [CGPoint] = []
                func collect(_ path: CGPath, into points: inout [CGPoint]) {
                    path.applyWithBlock { pointer in
                        let element = pointer.pointee
                        let count: Int
                        switch element.type {
                        case .moveToPoint, .addLineToPoint: count = 1
                        case .addQuadCurveToPoint: count = 2
                        case .addCurveToPoint: count = 3
                        case .closeSubpath: count = 0
                        @unknown default: count = 0
                        }
                        points.append(contentsOf: (0..<count).map { element.points[$0] })
                    }
                }
                collect(start, into: &first)
                collect(end, into: &last)
                #expect(first.count == last.count)
                #expect(zip(first, last).allSatisfy { abs($0.x - $1.x) < 0.00001 && abs($0.y - $1.y) < 0.00001 })
            }
            #expect(a.opacities == b.opacities)
        }
        let resting = BloubGeometry.frame(mode: .waiting, time: 0)
        let breathing = BloubGeometry.frame(mode: .waiting, time: 2.5, waitingMotion: .badge)
        #expect(breathing.notification.radius > resting.notification.radius)
        #expect(breathing.notification.opacity == resting.notification.opacity)
        #expect(breathing.eyes == resting.eyes)
        let blink = BloubGeometry.frame(mode: .waiting, time: 3.75, waitingMotion: .alive)
        #expect(blink.eyes.first!.boundingBoxOfPath.height < resting.eyes.first!.boundingBoxOfPath.height / 2)
    }

    @Test
    func waitingBlinksEveryFiveSeconds() {
        for mode in [UnifiedBars.Mode.waiting] {
            let reference = BloubGeometry.frame(mode: mode, time: 0, waitingMotion: .alive)
            var closingIntervals = 0
            var wasClosed = false
            for index in 0..<500 {
                let frame = BloubGeometry.frame(mode: mode, time: Double(index) / 20, waitingMotion: .alive)
                let closed = frame.eyes[0].boundingBoxOfPath.height < reference.eyes[0].boundingBoxOfPath.height / 2
                if closed && !wasClosed { closingIntervals += 1 }
                wasClosed = closed
            }
            #expect(closingIntervals == 5)
        }
    }

    @Test
    func idleKeepsItsOriginalBlinkSchedule() {
        #expect(BloubGeometry.loopPeriod(for: .idle) == 12)
        let reference = BloubGeometry.frame(mode: .idle, time: 0).eyes[0].boundingBoxOfPath.height
        for start in [1.4, 5.5, 9.4] {
            let closed = BloubGeometry.frame(mode: .idle, time: start + 0.081).eyes[0].boundingBoxOfPath.height
            let open = BloubGeometry.frame(mode: .idle, time: start + 0.3).eyes[0].boundingBoxOfPath.height
            #expect(closed < reference / 2)
            #expect(open > reference / 2)
        }
    }
}
