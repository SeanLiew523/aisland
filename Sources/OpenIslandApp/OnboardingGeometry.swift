import AppKit
import CoreGraphics

struct OnboardingGeometry: Equatable {
    let width: CGFloat
    let height: CGFloat
    let hardwareLeft: CGFloat
    let hardwareRight: CGFloat
    let hasHardwareNotch: Bool
    var centerX: CGFloat { (hardwareLeft + hardwareRight) / 2 }

    static func selectedScreen() -> NSScreen? {
        NSScreen.screens.first {
            let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return CGDisplayIsBuiltin(id) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func read(_ screen: NSScreen) -> Self {
        let frame = screen.frame
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let hasNotch = screen.safeAreaInsets.top > 0 && left != nil && right != nil
        let hardwareLeft = hasNotch ? left!.maxX - frame.minX : frame.width / 2
        let hardwareRight = hasNotch ? right!.minX - frame.minX : frame.width / 2
        return Self(width: hasNotch ? hardwareRight - hardwareLeft + 4 + 88 : 277,
                    height: max(32, screen.safeAreaInsets.top), hardwareLeft: hardwareLeft,
                    hardwareRight: hardwareRight, hasHardwareNotch: hasNotch)
    }
}

/// Shared by the view and tests; sprite clips hold their last frame while the
/// closed pill loops, exactly as the approved V6 canvas did.
enum OnboardingTimeline {
    static let duration = 22.0
    static let agents = 3.0, gather = 5.3, approval = 8.2, answer = 10.7
    static let back = 13.2, completed = 15.7, dock = 18.1, settled = 20.7
    static func frameIndex(time: Double, start: Double, fps: Double, frames: Int, looping: Bool = false) -> Int {
        let index = Int(max(0, time - start) * fps)
        return looping ? index % max(1, frames) : min(max(0, frames - 1), index)
    }
    static func scene(at time: Double) -> (key: String, start: Double)? {
        if time >= completed && time < dock { return ("completion", completed) }
        if time >= approval && time < answer { return ("approval", approval) }
        if time >= answer && time < back { return ("answer", answer) }
        if time >= back && time < completed { return ("sessions", back) }
        return nil
    }
}
