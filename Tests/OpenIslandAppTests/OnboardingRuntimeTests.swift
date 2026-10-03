import AppKit
import AVFoundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

struct OnboardingRuntimeTests {
    @Test func oneClockTracksAudioAndSilentPlayback() {
        let audio = OnboardingPlaybackClock(startUptime: 100.06,startAudioDeviceTime: 700.06)
        #expect(abs(audio.elapsed(uptime: 108.26,audioDeviceTime: 708.26)-8.2) < 0.00001)
        #expect(audio.elapsed(uptime: 100,audioDeviceTime: 700) == 0)
        let silent = OnboardingPlaybackClock(startUptime: 100,startAudioDeviceTime: nil)
        #expect(silent.elapsed(uptime: 122,audioDeviceTime: nil) == 22)
    }

    @Test func scenesHaveNoOverlapAndSpritesHoldInsteadOfDrifting() {
        #expect(OnboardingTimeline.scene(at: 8.199) == nil)
        #expect(OnboardingTimeline.scene(at: 8.2)?.key == "approval")
        #expect(OnboardingTimeline.scene(at: 10.7)?.key == "answer")
        #expect(OnboardingTimeline.scene(at: 13.2)?.key == "sessions")
        #expect(OnboardingTimeline.scene(at: 15.7)?.key == "completion")
        #expect(OnboardingTimeline.scene(at: 18.1) == nil)
        #expect(OnboardingTimeline.frameIndex(time: 10.69,start: 8.2,fps: 30,frames: 51) == 50)
        #expect(OnboardingTimeline.frameIndex(time: 20,start: 18.1,fps: 30,frames: 38,looping: true) == 18)
    }

    @Test @MainActor func bothLanguagesLoadAllApprovedNativeFramesAndScore() throws {
        for language in OnboardingLanguage.allCases {
            let media = try OnboardingMedia(language: language)
            #expect(media.logos.count == 9)
            #expect(media.rows.count == 4)
            #expect(Set(media.clips.keys) == Set(["approval","answer","sessions","completion","closed"]))
            #expect(media.clips["approval"]?.frames.count == 51)
            #expect(media.clips["answer"]?.frames.count == 33)
            #expect(media.clips["sessions"]?.frames.count == 62)
            #expect(media.clips["completion"]?.frames.count == 56)
            #expect(media.clips["closed"]?.frames.count == 38)
            for clip in media.clips.values {
                #expect(clip.frames.allSatisfy { $0.width == clip.metadata.width && $0.height == clip.metadata.height })
            }
        }
        let url = try #require(Bundle.appResources.url(forResource: "intro-v6",withExtension: "wav"))
        let file = try AVAudioFile(forReading: url)
        #expect(file.processingFormat.sampleRate == 48000)
        #expect(file.processingFormat.channelCount == 2)
        #expect(Double(file.length)/file.processingFormat.sampleRate == OnboardingTimeline.duration)
    }

    @Test @MainActor func nativeRendererProducesEverySceneWithoutOpeningWindow() throws {
        let geometry = OnboardingGeometry(width: 302,height: 32,hardwareLeft: 650,hardwareRight: 860,hasHardwareNotch: true)
        for language in OnboardingLanguage.allCases {
            let media = try OnboardingMedia(language: language)
            let view = OnboardingSceneView(media: media,language: language,geometry: geometry)
            view.frame = CGRect(x: 0,y: 0,width: 1512,height: 982)
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: 1512,pixelsHigh: 982,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            let previous = NSGraphicsContext.current
            defer { NSGraphicsContext.current = previous }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext,flipped: true)
            context.cgContext.translateBy(x: 0,y: 982)
            context.cgContext.scaleBy(x: 1,y: -1)
            for reduced in [false,true] {
                view.reduceMotion = reduced
                for time in [1.4,3.8,6.8,8.5,11.1,14.0,16.0,19.0,21.5] {
                    view.time = time
                    view.draw(view.bounds)
                    #expect(bitmap.colorAt(x: 100,y: 100)?.alphaComponent == 1)
                    if !reduced, let output = ProcessInfo.processInfo.environment["AISLAND_ONBOARDING_FRAME_DIRECTORY"] {
                        let directory = URL(fileURLWithPath: output,isDirectory: true)
                        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
                        try bitmap.representation(using: .png,properties: [:])?.write(to: directory.appendingPathComponent("intro-\(language.rawValue)-\(time).png"))
                    }
                }
            }
        }
    }
}
