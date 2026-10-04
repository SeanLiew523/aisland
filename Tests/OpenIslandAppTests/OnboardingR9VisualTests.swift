import AppKit
import CryptoKit
import Testing
import OpenIslandCore
@testable import OpenIslandApp

struct OnboardingR9VisualTests {
    @Test func geometryMatchesApprovedPrototypeAtEveryViewportAndResize() throws {
        for reduced in [false, true] {
            for size in [CGSize(width: 380,height: 500), CGSize(width: 1702,height: 1016),
                         CGSize(width: 380,height: 500), CGSize(width: 3440,height: 1440)] {
                let orbit = try #require(OnboardingBrandGeometry.orbit(time: 21.1,bounds: size,reduceMotion: reduced))
                #expect(orbit.rect.width == min(size.width*0.68,size.height*0.66)*0.7)
                #expect(abs(orbit.rect.midX-size.width/2)<0.000001)
                #expect(abs(orbit.rect.midY-size.height*0.55)<0.000001)
                #expect(orbit.rect.minY>0 && orbit.rect.maxY<size.height)
                #expect(orbit.sampleTime == (reduced ? 2.5 : (21.1-OnboardingTimeline.orbitStart)*1.1))
            }
        }
        let bounds = CGSize(width: 1728,height: 1080)
        #expect(OnboardingBrandGeometry.orbit(time: 18.899,bounds: bounds,reduceMotion: false) == nil)
        #expect(OnboardingBrandGeometry.orbit(time: OnboardingTimeline.orbitStart,bounds: bounds,reduceMotion: false)?.opacity == 0)
        #expect(OnboardingBrandGeometry.orbit(time: 19.3,bounds: bounds,reduceMotion: false)?.opacity == 1)
        #expect(OnboardingBrandGeometry.orbit(time: 22,bounds: bounds,reduceMotion: false)?.sampleTime == 3.3)
        let island = CGRect(x: 700,y: 400,width: 218,height: 70)
        let idle = try #require(OnboardingBrandGeometry.gather(time: 7.949,island: island,reduceMotion: false))
        let thinking = try #require(OnboardingBrandGeometry.gather(time: 7.95,island: island,reduceMotion: false))
        #expect(idle.state == "idle" && thinking.state == "thinking")
        #expect(idle.rect == thinking.rect)
        #expect(abs(idle.rect.midX-(island.midX-island.width*0.35))<0.000001)
        #expect(idle.rect.width == island.height*0.82)
        #expect(idle.rect.minX>island.minX && idle.rect.maxX<island.midX)
        #expect(OnboardingBrandGeometry.gather(time: 5.299,island: island,reduceMotion: true) == nil)
        #expect(OnboardingBrandGeometry.gather(time: 8.2,island: island,reduceMotion: true) == nil)
        #expect(OnboardingBrandGeometry.gather(time: 8.1,island: island,reduceMotion: true)?.sampleTime == 1)
    }

    @Test @MainActor func originalEngineResourceInventoryAndBoundedCache() throws {
        let media = try OnboardingBrandMedia()
        let provenanceURL = try #require(Bundle.appResources.url(forResource:"bloub-r9-provenance",withExtension:"json"))
        let provenance = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: provenanceURL)) as? [String:Any])
        let hashes = try #require(provenance["generated_files_sha256"] as? [String:String])
        #expect(hashes.count == 191)
        for (file, expected) in hashes {
            let name = file as NSString
            let url = try #require(Bundle.appResources.url(forResource:name.deletingPathExtension,withExtension:name.pathExtension))
            let actual = SHA256.hash(data:try Data(contentsOf:url)).map { String(format:"%02x",$0) }.joined()
            #expect(actual == expected)
        }
        let manifestURL = try #require(Bundle.appResources.url(forResource:"bloub-r9",withExtension:"json"))
        #expect(SHA256.hash(data:try Data(contentsOf:manifestURL)).map { String(format:"%02x",$0) }.joined() == provenance["manifest_sha256"] as? String)
        #expect(media.decodedMotionFrameCount == 0)
        let thinking = try #require(media.manifest.sequences["thinking"])
        #expect(thinking.frameIndex(sampleTime:7.95) == 0)
        #expect(thinking.frameIndex(sampleTime:7.966666667) == 1)
        #expect(thinking.frameIndex(sampleTime:8.0) == 2)
        var decodeTimes: [Double] = []
        for (state, sequence) in media.manifest.sequences {
            for index in sequence.files.indices {
                let start = ProcessInfo.processInfo.systemUptime
                let image = try #require(media.image(state:state,sampleTime:sequence.sampleStart+Double(index)/30,reduceMotion:false))
                #expect(image.width == sequence.width && image.height == sequence.height)
                decodeTimes.append((ProcessInfo.processInfo.systemUptime-start)*1000)
                #expect(media.decodedMotionFrameCount<=3)
            }
            let still = try #require(media.image(state:state,sampleTime:99,reduceMotion:true))
            let other = try #require(media.image(state:state,sampleTime:0,reduceMotion:true))
            #expect(still === other)
            let last = try #require(media.image(state:state,sampleTime:99,reduceMotion:false))
            let lastAgain = try #require(media.image(state:state,sampleTime:99,reduceMotion:false))
            #expect(last === lastAgain)
        }
        #expect(media.decodedMotionFrameCount == 3)
        #expect(media.compressedByteCount<32*1024*1024)
        decodeTimes.sort()
        print("R9 original-engine PNG decode: frames=\(decodeTimes.count), compressedBytes=\(media.compressedByteCount), maxMs=\(decodeTimes.last ?? 0), p95Ms=\(decodeTimes[Int(Double(decodeTimes.count-1)*0.95)])")
    }

    @Test @MainActor func nativeOffscreenHasNoOpeningCopyAndRendersAllNewPoses() throws {
        let geometry = OnboardingGeometry(width:302,height:32,hardwareLeft:650,hardwareRight:860,hasHardwareNotch:true)
        let media = try OnboardingMedia(language:.chinese)
        let en = try OnboardingMedia(language:.english)
        func render(_ media: OnboardingMedia, _ language: OnboardingLanguage, _ size: CGSize,
                    _ time: Double, _ reduced: Bool) throws -> NSBitmapImageRep {
            let view = OnboardingSceneView(media:media,language:language,geometry:geometry)
            view.frame = CGRect(origin:.zero,size:size);view.time=time;view.reduceMotion=reduced
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
            let context = try #require(NSGraphicsContext(bitmapImageRep:bitmap))
            let previous = NSGraphicsContext.current;defer { NSGraphicsContext.current=previous }
            NSGraphicsContext.current=NSGraphicsContext(cgContext:context.cgContext,flipped:true)
            context.cgContext.translateBy(x:0,y:size.height);context.cgContext.scaleBy(x:1,y:-1)
            view.draw(view.bounds)
            if let output = ProcessInfo.processInfo.environment["AISLAND_ONBOARDING_FRAME_DIRECTORY"] {
                let directory=URL(fileURLWithPath:output,isDirectory:true)
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                try bitmap.representation(using:.png,properties:[:])?.write(to:directory.appendingPathComponent("r9-\(language.rawValue)-\(Int(size.width))x\(Int(size.height))-\(time)\(reduced ? "-reduced" : "").png"))
            }
            return bitmap
        }
        let openingSize=CGSize(width:970,height:606)
        let zhOpening=try render(media,.chinese,openingSize,1.4,false)
        let enOpening=try render(en,.english,openingSize,1.4,false)
        // A V6 title changed the pixels between locales; the R9 stage has no
        // descriptive title. The unchanged corner AIsland brand is identical.
        #expect(Data(bytes:try #require(zhOpening.bitmapData),count:zhOpening.bytesPerRow*zhOpening.pixelsHigh) == Data(bytes:try #require(enOpening.bitmapData),count:enOpening.bytesPerRow*enOpening.pixelsHigh))
        for (language, m) in [(OnboardingLanguage.chinese,media),(.english,en)] {
            for size in [CGSize(width:380,height:500),CGSize(width:1702,height:1016)] {
                for reduced in [false,true] {
                    for time in [6.6,8.1,19.8,21.6] {
                        let bitmap=try render(m,language,size,time,reduced)
                        #expect(bitmap.colorAt(x:100,y:100)?.alphaComponent==1)
                    }
                }
            }
        }
    }
}
