//
//  RecordEngine.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/17.
//

import Foundation
import UserNotifications
import ScreenCaptureKit
import AVFoundation
import AVFAudio
import VideoToolbox
import AECAudioStream
import HaishinKit
import SRTHaishinKit

import AudioToolbox   // for kAudioFormatMPEG4AAC


extension AppDelegate {
    @objc func prepRecord(type: String, screens: SCDisplay?, windows: [SCWindow]?, applications: [SCRunningApplication]?, fastStart: Bool = false) {
        switch type {
        case "window":  SCContext.streamType = .window
        case "windows":  SCContext.streamType = .windows
        case "display": SCContext.streamType = .screen
        case "application": SCContext.streamType = .application
        case "area": SCContext.streamType = .screenarea
        case "audio":   SCContext.streamType = .systemaudio
            default: return // if we don't even know what to record I don't think we should even try
        }
        var isDirectory: ObjCBool = false
        let outputPath = saveDirectory!
        if fd.fileExists(atPath: outputPath, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                SCContext.streamType = nil
                _ = createAlert(title: "Failed to Record".local, message: "The output path is a file instead of a folder!".local, button1: "OK").runModal()
                return
            }
        } else {
            do {
                try fd.createDirectory(atPath: outputPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                SCContext.streamType = nil
                _ = createAlert(title: "Failed to Record".local, message: "Unable to create output folder!".local, button1: "OK").runModal()
                return
            }
        }
        
        // file preparation
        if let screens = screens {
            SCContext.screen = SCContext.availableContent!.displays.first(where: { $0 == screens })
        } else { SCContext.streamType = nil; return }
        
        if let windows = windows {
            SCContext.window = SCContext.availableContent!.windows.filter({ windows.contains($0) })
        } else { if SCContext.streamType == .window { SCContext.streamType = nil; return } }
        
        if let applications = applications {
            SCContext.application = SCContext.availableContent!.applications.filter({ applications.contains($0) })
        } else { if SCContext.streamType == .application { SCContext.streamType = nil; return } }
        
        let screen = SCContext.screen ?? SCContext.getSCDisplayWithMouse()!
        let qrSelf = SCContext.getSelf()
        let qrWindows = SCContext.getSelfWindows()
        let dockApp = SCContext.availableContent!.applications.first(where: { $0.bundleIdentifier.description == "com.apple.dock" })
        let wallpaper = SCContext.availableContent!.windows.filter({
            guard let title = $0.title else { return false }
            return $0.owningApplication?.bundleIdentifier == "com.apple.dock" && title != "LPSpringboard" && title != "Dock"
        })
        let desktop = SCContext.availableContent!.windows.filter({
            guard let title = $0.title else { return false }
            return $0.owningApplication?.bundleIdentifier == "" && title == "Desktop"
        })
        let dockWindow = SCContext.availableContent!.windows.filter({
            guard let title = $0.title else { return true }
            return $0.owningApplication?.bundleIdentifier == "com.apple.dock" && title == "Dock"
        })
        let desktopFiles = SCContext.availableContent!.windows.filter({
            $0.owningApplication?.bundleIdentifier == "com.apple.finder"
            && $0.title == "" && $0.frame == screen.frame })
        let controlCenterWindow = SCContext.availableContent!.applications.filter({ $0.bundleIdentifier == "com.apple.controlcenter" })
        let mouseWindow = SCContext.availableContent!.windows.filter({ $0.title == "Mouse Pointer".local && $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier })
        let camLayer = SCContext.availableContent!.windows.filter({ $0.title == "Camera Overlayer".local && $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier })
        var appBlackList = [String]()
        if let savedData = ud.data(forKey: "hiddenApps"),
           let decodedApps = try? JSONDecoder().decode([AppInfo].self, from: savedData) {
            appBlackList = (decodedApps as [AppInfo]).map({ $0.bundleID })
        }
        let excliudedApps = SCContext.availableContent!.applications.filter({ appBlackList.contains($0.bundleIdentifier) })
        
        if SCContext.streamType == .window || SCContext.streamType == .windows {
            if var includ = SCContext.window {
                if includ.count > 1 {
                    if highlightMouse { includ += mouseWindow }
                    if background.rawValue == BackgroundType.wallpaper.rawValue { if dockApp != nil { includ += wallpaper }}
                    SCContext.filter = SCContentFilter(display: screen, including: includ + camLayer)
                    if #available(macOS 14.2, *) { SCContext.filter?.includeMenuBar = includeMenuBar }
                } else {
                    SCContext.streamType = .window
                    SCContext.filter = SCContentFilter(desktopIndependentWindow: includ[0])
                }
            }
        } else {
            if SCContext.streamType == .screen || SCContext.streamType == .screenarea {
                if SCContext.streamType == .screenarea {
                    if let area = SCContext.screenArea, let name = screen.nsScreen?.localizedName {
                        let a = ["x": area.origin.x, "y": area.origin.y, "width": area.width, "height": area.height]
                        ud.set([name: a], forKey: "savedArea")
                    }
                }
                var excluded = [SCRunningApplication]()
                var except = [SCWindow]()
                excluded += excliudedApps
                if hideCCenter { excluded += controlCenterWindow }
                if hideSelf { if let qrWindows = qrWindows { except += qrWindows }}
                if background.rawValue != BackgroundType.wallpaper.rawValue { if dockApp != nil {
                    except += wallpaper
                    except += desktop
                }}
                if hideDesktopFiles { except += desktopFiles }
                SCContext.filter = SCContentFilter(display: screen, excludingApplications: excluded, exceptingWindows: except)
                if #available(macOS 14.2, *) { SCContext.filter?.includeMenuBar = ((SCContext.streamType == .screen || SCContext.streamType == .screenarea) && includeMenuBar) }
            }
            if SCContext.streamType == .application {
                var includ = SCContext.application!
                var except = [SCWindow]()
                if let qrSelf = qrSelf { includ.append(qrSelf) }
                let withFinder = includ.map{ $0.bundleIdentifier }.contains("com.apple.finder")
                if withFinder && hideDesktopFiles { except += desktopFiles }
                if hideSelf { if let qrWindows = qrWindows { except += qrWindows }}
                //if ud.bool(forKey: "highlightMouse") { if let qrSelf = qrSelf { includ.append(qrSelf) }}
                if background.rawValue == BackgroundType.wallpaper.rawValue { if let dock = dockApp { includ.append(dock); except += dockWindow}}
                SCContext.filter = SCContentFilter(display: screen, including: includ, exceptingWindows: except)
                if #available(macOS 14.2, *) { SCContext.filter?.includeMenuBar = includeMenuBar }
            }
        }
        if SCContext.streamType == .systemaudio {
            SCContext.filter = SCContentFilter(display: screen, excludingApplications: [], exceptingWindows: [])
            prepareAudioRecording()
        }
        Task { await record(filter: SCContext.filter!, fastStart: fastStart) }
    }

    func record(filter: SCContentFilter, fastStart: Bool = true) async {
        SCContext.timeOffset = CMTimeMake(value: 0, timescale: 0)
        SCContext.isPaused = false
        SCContext.isResume = false
        
        let audioOnly = SCContext.streamType == .systemaudio
        
        let conf: SCStreamConfiguration
#if compiler(>=6.0)
        if recordHDR {
            if #available(macOS 15, *) {
                // TODO change here. https://developer.apple.com/videos/play/wwdc2024/10088/?time=191
                // For canonical display, it means you are capturing HDR content that is optimized for sharing with other HDR devices.
                // hdrLocalDisplay or hdrCanonicalDisplay


                conf = SCStreamConfiguration(preset: .captureHDRStreamLocalDisplay)
            } else { conf = SCStreamConfiguration() }
        } else { conf = SCStreamConfiguration() }
#else
        conf = SCStreamConfiguration()
#endif
        conf.width = 2
        conf.height = 2
        
        if !audioOnly {
            if #available(macOS 14.0, *) {
                conf.width = Int(filter.contentRect.width) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
                conf.height = Int(filter.contentRect.height) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
            } else {
                guard let pointPixelScaleOld = (SCContext.screen ?? SCContext.getSCDisplayWithMouse()!).nsScreen?.backingScaleFactor else { return }
                if SCContext.streamType == .application || SCContext.streamType == .windows || SCContext.streamType == .screen {
                    let frame = (SCContext.screen ?? SCContext.getSCDisplayWithMouse()!).frame
                    conf.width = Int(frame.width)
                    conf.height = Int(frame.height)
                }
                if SCContext.streamType == .window {
                    let frame = SCContext.window![0].frame
                    conf.width = Int(frame.width)
                    conf.height = Int(frame.height)
                }
                if SCContext.streamType == .screenarea {
                    let frame = SCContext.screenArea!
                    conf.width = Int(frame.width)
                    conf.height = Int(frame.height)
                }
                conf.width = conf.width * (highRes == 2 ? Int(pointPixelScaleOld) : 1)
                conf.height = conf.height * (highRes == 2 ? Int(pointPixelScaleOld) : 1)
            }
            
            if fastStart{
                conf.showsCursor = false
            } else{
                conf.showsCursor = showMouse
            }
                    

            if background.rawValue != BackgroundType.wallpaper.rawValue { conf.backgroundColor = SCContext.getBackgroundColor() }
            if !recordHDR {
                conf.pixelFormat = kCVPixelFormatType_32BGRA
                conf.colorSpaceName = CGColorSpace.sRGB
                //if withAlpha { conf.pixelFormat = kCVPixelFormatType_32BGRA }
            } else {
                // For recording HDR in a BT2020 PQ container
                conf.colorSpaceName = CGColorSpace.itur_2100_PQ
//                https://developer.apple.com/videos/play/wwdc2022/10155/ guide on how to record 4k60
//                streamConfiguration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    
// Note: 420 encoding causes color bleed at edges, e.g. youtube settings icon with red logo
                // conf.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
//              dont exceed 8 frames  https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth
//                lower queuedepth has more stutter, dont go below 4 https://github.com/nonstrict-hq/ScreenCaptureKit-Recording-example/blob/main/Sources/sckrecording/main.swift
                conf.queueDepth = 8
            }
        }
        
        if #available(macOS 13, *) {
            conf.capturesAudio = recordWinSound || fastStart || audioOnly
            conf.sampleRate = 48000
            conf.channelCount = 2
        }
        

        //  conf.minimumFrameInterval = CMTime(value: 1, timescale: audioOnly ? CMTimeScale.max : CMTimeScale(frameRate))
         conf.minimumFrameInterval = CMTime(value: 1, timescale: audioOnly ? CMTimeScale.max : (frameRate >= 60 ? 0 : CMTimeScale(frameRate)))

//        CMTimeScale is the denominator in the fraction
//        conf.minimumFrameInterval = CMTime(seconds: audioOnly ? Double(CMTimeScale.max) : Double(1)/Double(frameRate), preferredTimescale: 10000)

        // note: ScreenCaptureKit only delivers frames when something changes
        // https://www.reddit.com/r/swift/comments/158n4c9/comment/ju847rm/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button

        //blog post from the reddit comment https://nonstrict.eu/blog/2023/recording-to-disk-with-screencapturekit/

        //https://github.com/nonstrict-hq/ScreenCaptureKit-Recording-example

        // https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/minimumframeinterval
        //minimumFrameInterval: Use this value to throttle the rate at which you receive updates. The default value is 0, which indicates that the system uses the maximum supported frame rate.

        print("Frame interval passed to ScreenCaptureKit. (timescale is FPS. 0 means no throttling): \(conf.minimumFrameInterval)")
        

        if SCContext.streamType == .screenarea {
            if let nsRect = SCContext.screenArea {
                let newY = SCContext.screen!.frame.height - nsRect.size.height - nsRect.origin.y
                conf.sourceRect = CGRect(x: nsRect.origin.x, y: newY, width: nsRect.size.width, height: nsRect.size.height)
                if #available(macOS 14.0, *) {
                    conf.width = Int(conf.sourceRect.width) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
                    conf.height = Int(conf.sourceRect.height) * (highRes == 2 ? Int(filter.pointPixelScale) : 1)
                } else {
                    guard let pointPixelScaleOld = (SCContext.screen ?? SCContext.getSCDisplayWithMouse()!).nsScreen?.backingScaleFactor else { return }
                    conf.width = Int(conf.sourceRect.width) * (highRes == 2 ? Int(pointPixelScaleOld) : 1)
                    conf.height = Int(conf.sourceRect.height) * (highRes == 2 ? Int(pointPixelScaleOld) : 1)
                }
            }
        }
        
        let encoderIsH265 = (encoder.rawValue == Encoder.h265.rawValue) || recordHDR
        if !audioOnly && !encoderIsH265 {
            var session: VTCompressionSession?
            let status = VTCompressionSessionCreate(
                allocator: nil,
                width: Int32(conf.width),
                height: Int32(conf.height),
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true] as CFDictionary,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: nil,
                refcon: nil,
                compressionSessionOut: &session
            )
            
            if status != noErr {
                let button = showAlertSyncOnMainThread(
                    level: .critical,
                    title: "Encoder Warning",
                    message: "VideoToolbox H.264 hardware encoder doesn't support the current resolution.\nContinue with a software encoder will significantly increase the CPU usage.\n\nWould you like to use H.265 instead?".local,
                    button1: "Use H.265",
                    button2: "Continue with H.264"
                )
                if button == .alertFirstButtonReturn { ud.setValue(Encoder.h265.rawValue, forKey: "encoder") }
            }
        }
        
        SCContext.stream = SCStream(filter: filter, configuration: conf, delegate: self)
        do {
            try SCContext.stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            if #available(macOS 13, *) { try SCContext.stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global()) }
            
            // Check if recording to file is enabled
            let enableRecording = ud.bool(forKey: "enableRecording")
            
            if !audioOnly {
                initVideo(conf: conf)
                
                // For streaming-only mode, ensure microphone recording is set up
                if recordMic && !enableRecording {
                    // Microphone will be started when the first video frame arrives,
                    // but we need to ensure the flag is ready
                    print("Microphone recording will start for streaming-only mode")
                }
            } else if audioOnly && enableRecording {
                //SCContext.startTime = Date.now
                if recordMic && SCContext.streamType == .systemaudio { 
                    // For audio-only recording with mic, startMicRecording will be called
                    // when the first system audio sample arrives and starts the session
                } else if recordMic {
                    // For other cases where mic is needed but no video
                    let sampleRate = SCContext.getSampleRate() ?? 48000
                    let settings = SCContext.updateAudioSettings(rate: sampleRate)
                    
                    SCContext.micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings)
                    SCContext.micInput.expectsMediaDataInRealTime = true
                    if SCContext.vW?.canAdd(SCContext.micInput) == true { SCContext.vW.add(SCContext.micInput) }
                    SCContext.vW?.startWriting()
                    SCContext.micRecordingStarted = true
                    startMicRecording()
                }
            } else if audioOnly && recordMic {
                // Audio-only streaming mode - set up microphone recording for streaming
                print("Setting up microphone for audio-only streaming mode")
                // Microphone will be started when the first audio sample arrives
            } else {
                print("No microphone recording needed - recording and streaming disabled or no mic selected")
            }
           
            // Check if RTMP streaming is enabled and configured
            let enableRTMPStreaming = ud.bool(forKey: "enableRTMPStreaming")
            let rtmpBaseURL = ud.string(forKey: "rtmpURL") ?? "rtmp://127.0.0.1:1935/live"
            let streamKey = ud.string(forKey: "streamKey") ?? "live"
            let fullURL = "\(rtmpBaseURL)/\(streamKey)"
            
            if enableRTMPStreaming {
                // Use single-track audio mixing for better compatibility
                let mixer = MediaMixer(multiTrackAudioMixingEnabled: false)
                SCContext.mixer = mixer

                // Configure mixer for offscreen video mixing (like the example)
                var videoMixerSettings = await mixer.videoMixerSettings
                videoMixerSettings.mode = .passthrough//.offscreen
                videoMixerSettings.mainTrack = 0  // Screen capture will be on track 0
                
                await mixer.setVideoMixerSettings(videoMixerSettings)
                
                // Configure audio mixer for single-track mixing (all audio on track 0)
                var audioMixerSettings = await mixer.audioMixerSettings
                audioMixerSettings.mainTrack = 0  // All audio will be sent to track 0
                audioMixerSettings.isMuted = false
                // Configure track settings for proper mixing
                audioMixerSettings.tracks[0] = AudioMixerTrackSettings(volume: 1.0, isMuted: false, channelMap: [0])  // mic
                audioMixerSettings.tracks[1] = AudioMixerTrackSettings(volume: 1.0, isMuted: false, channelMap: [0, 1])  // system audio
                await mixer.setAudioMixerSettings(audioMixerSettings)
                await mixer.setMonitoringEnabled(true)
                print("Audio mixer configured: mainTrack=0, single-track mixing enabled, all audio on track 0")
                
                // DEBUG: Check if mixer is properly configured
                let currentSettings = await mixer.audioMixerSettings
                print("🔍 [DEBUG] Audio mixer settings: mainTrack=\(currentSettings.mainTrack), tracks=\(currentSettings.tracks.keys.sorted())")
                print("🔍 [DEBUG] Multi-track audio mixing enabled: \(await mixer.isMultiTrackAudioMixingEnabled)")

                // Create RTMP session using SessionBuilderFactory (like the example)
                guard let url = URL(string: fullURL),
                      let session = await SessionBuilderFactory.shared.make(url)?.build() else {
                    print("Failed to create RTMP session with URL: \(fullURL)")
                    return
                }
                
                guard let rtmpStream = await session.stream as? RTMPStream else {
                    print("Failed to get RTMP stream from session")
                    return
                }
                
                // Configure video codec settings based on user preferences and capture dimensions
                let streamBitrate = ud.integer(forKey: "streamBitrate") != 0 ? ud.integer(forKey: "streamBitrate") : 1000
                let streamScaler = ud.string(forKey: "streamScaler") ?? "1x"
                
                // Calculate streaming resolution based on the actual capture context and scaler
                var baseResolution: CGSize
                if let screen = SCContext.screen {
                    baseResolution = screen.frame.size
                    let backingScale = screen.nsScreen?.backingScaleFactor ?? 1.0
                    baseResolution.width = baseResolution.width * backingScale
                    baseResolution.height = baseResolution.height * backingScale
                } else if let window = SCContext.window?.first {
                    baseResolution = window.frame.size
                } else if let application = SCContext.application?.first {
                    // For applications, use the screen size as base
                    baseResolution = (SCContext.screen ?? SCContext.getSCDisplayWithMouse()!).frame.size
                } else {
                    // Fallback to main screen
                    baseResolution = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
                }
                
                // Apply scaler multiplier
                let multiplier: Double
                switch streamScaler {
                case "1x", "original": multiplier = 1.0
                case "0.75x": multiplier = 0.75
                case "0.5x": multiplier = 0.5
                case "0.25x": multiplier = 0.25
                default: multiplier = 1.0
                }
                
                var finalStreamWidth = Int(baseResolution.width * multiplier)
                var finalStreamHeight = Int(baseResolution.height * multiplier)
                
                // Ensure even numbers for encoder compatibility
                finalStreamWidth = finalStreamWidth - (finalStreamWidth % 2)
                finalStreamHeight = finalStreamHeight - (finalStreamHeight % 2)

                // Auto-correlate to closest standard aspect ratio size
                let standardSizes: [(width: Int, height: Int, name: String)] = [
                    (7680, 4320, "4320p (8K)"),
                    (3840, 2160, "2160p (4K)"),
                    (2560, 1440, "1440p (2K)"),
                    (1920, 1080, "1080p (HD)"),
                    (1280, 720, "720p (HD)"),
                    (854, 480, "480p (SD)"),
                    (640, 360, "360p (SD)"),
                    (426, 240, "240p (SD)")
                ]
                
                // Find the closest standard size based on total pixel count
                let currentPixelCount = finalStreamWidth * finalStreamHeight
                var closestSize = standardSizes.last! // Default to smallest size
                var smallestDifference = Int.max
                
                for size in standardSizes {
                    let sizePixelCount = size.width * size.height
                    let difference = abs(currentPixelCount - sizePixelCount)
                    if difference < smallestDifference {
                        smallestDifference = difference
                        closestSize = size
                    }
                }
                
                // Update to standard size
                finalStreamWidth = closestSize.width
                finalStreamHeight = closestSize.height

                print("🔄 Streaming resolution calculated: \(Int(baseResolution.width))x\(Int(baseResolution.height)) (base) → \(finalStreamWidth)x\(finalStreamHeight) (\(closestSize.name), scaler: \(streamScaler))")

                // Use the codec from stream settings, but fall back to the main encoder setting from Output tab
                let streamCodec = ud.string(forKey: "streamCodec") ?? (encoder.rawValue == Encoder.h265.rawValue ? "h265" : "h264")
                let encoderIsH265 = (streamCodec == "h265") || recordHDR
                
                // Calculate automatic bitrate if enabled, using the actual streaming resolution
                let streamAutoBitrate = ud.bool(forKey: "streamAutoBitrate")
                var finalBitrate = streamBitrate * 1000 // Convert kbps to bps
                
                if streamAutoBitrate {
                    let frameRate = ud.integer(forKey: "frameRate") != 0 ? ud.integer(forKey: "frameRate") : 30
                    let fpsMultiplier: Double = Double(frameRate) / 8
                    let encoderMultiplier: Double = (streamCodec == "h265") ? 0.5 : 0.9
                    let pixelCount = Double(max(600, finalStreamWidth)) * Double(max(600, finalStreamHeight))
                    
                    // Adjust for retina displays - slightly reduce multiplier since we have higher pixel density
                    var qualityMultiplier: Double = 1.0
                    if let mainScreen = NSScreen.main, mainScreen.backingScaleFactor > 1.0 {
                        qualityMultiplier = 0.8
                    }
                    
                    let targetBitrate = Int(pixelCount * fpsMultiplier * encoderMultiplier * qualityMultiplier)
                    let calculatedBitrate = max(1000, targetBitrate / 1000) // Convert to kbps and ensure minimum 1000kbps
                    finalBitrate = calculatedBitrate * 1000 // Convert back to bps
                    
                    print("🔄 Automatic bitrate calculated: \(calculatedBitrate)kbps (based on \(finalStreamWidth)x\(finalStreamHeight), \(frameRate)fps, \(streamCodec))")
                    
                    // Update the stored bitrate value for UI consistency
                    ud.set(calculatedBitrate, forKey: "streamBitrate")
                } else {
                    print("📊 Using manual bitrate: \(streamBitrate)kbps")
                }
            
                let videoCodecSettings = VideoCodecSettings(
                    videoSize: CGSize(width: finalStreamWidth, height: finalStreamHeight),
                    bitRate: finalBitrate,
                    profileLevel: encoderIsH265 ? kVTProfileLevel_HEVC_Main_AutoLevel as String : kVTProfileLevel_H264_High_AutoLevel as String,
                    maxKeyFrameIntervalDuration: 2,
                    allowFrameReordering: false,
                    isHardwareEncoderEnabled: true
                )
                
                await rtmpStream.setVideoSettings(videoCodecSettings)
                print("✅ RTMP video codec configured: \(encoderIsH265 ? "HEVC" : "H264"), \(finalStreamWidth)x\(finalStreamHeight), \(finalBitrate/1000)kbps")
                
                // Configure audio codec settings based on user preferences
                let streamAudioCodec = ud.string(forKey: "streamAudioCodec") ?? "aac"
                let streamAudioQuality = ud.string(forKey: "streamAudioQuality") ?? "normal"
                
                // Map audio quality to bitrate
                let audioBitrate: Int
                switch streamAudioQuality {
                case "low": audioBitrate = 64000
                case "normal": audioBitrate = 128000
                case "good": audioBitrate = 192000
                case "high": audioBitrate = 256000
                case "extreme": audioBitrate = 320000
                default: audioBitrate = 128000 // Default to normal quality (128kbps)
                }
                
                // Configure audio codec settings
                var audioCodecSettings = AudioCodecSettings()
                audioCodecSettings.bitRate = audioBitrate
                
                // Set the audio codec based on user selection
                switch streamAudioCodec {
                case "opus":
                    audioCodecSettings.format = .opus
                case "aac":
                    fallthrough
                default:
                    audioCodecSettings.format = .aac
                }
                
                await rtmpStream.setAudioSettings(audioCodecSettings)
                print("✅ RTMP audio codec configured: \(streamAudioCodec.uppercased()), \(audioBitrate/1000)kbps")
          
                
                SCContext.session = session
                await mixer.addOutput(rtmpStream)
                print("✅ RTMP stream added as mixer output")
                
                // Connect to RTMP endpoint
                Task {
                    do {
                        try await session.connect(.ingest)
                        print("✅ Successfully connected to RTMP endpoint: \(fullURL)")
                    } catch {
                        print("❌ Failed to connect to RTMP endpoint: \(error)")
                    }
                }
            } else {
                print("RTMP streaming is disabled - no mixer created")
                SCContext.mixer = nil
            }
            try await SCContext.stream.startCapture()
            //try await SCContext.rtmpPusher.publish()
        } catch {
            assertionFailure("capture failed".local)
            return
        }
        if !audioOnly { registerGlobalMouseMonitor() }
        DispatchQueue.main.async { updateStatusBar() }
        if preventSleep { SleepPreventer.shared.preventSleep(reason: "Screen recording in progress") }
    }

    func prepareAudioRecording() {
        var fileEnding = audioFormat.rawValue
        var fileType = AVFileType.m4a
        let encorder = fileEnding == AudioFormat.mp3.rawValue ? "aac" : fileEnding
        switch fileEnding { // todo: I'd like to store format info differently
            case AudioFormat.mp3.rawValue: fallthrough
            case AudioFormat.aac.rawValue: fallthrough
            case AudioFormat.alac.rawValue: fileEnding = "m4a"
            case AudioFormat.flac.rawValue: fileEnding = "flac"; fileType = .caf
            case AudioFormat.opus.rawValue: fileEnding = "ogg"; fileType = .caf
            default: assertionFailure("loaded unknown audio format: ".local + fileEnding)
        }
        let path = SCContext.getFilePath()
        if recordMic && SCContext.streamType == .systemaudio {
            SCContext.filePath = "\(path).qma"
            SCContext.filePath1 = "\(path).qma/sys.\(fileEnding)"
            SCContext.filePath2 = "\(path).qma/mic.\(fileEnding)"
            let infoJsonURL = "\(path).qma/info.json".url
            let jsonString = "{\"format\": \"\(fileEnding)\", \"encoder\": \"\(encorder)\", \"exportMP3\": \(audioFormat.rawValue == AudioFormat.mp3.rawValue), \"sysVol\": 1.0, \"micVol\": 1.0}"
            try? fd.createDirectory(at: SCContext.filePath.url, withIntermediateDirectories: true, attributes: nil)
            try? jsonString.write(to: infoJsonURL, atomically: true, encoding: .utf8)
            
            SCContext.audioFile = try! AVAudioFile(forWriting: SCContext.filePath1.url, settings: SCContext.updateAudioSettings(), commonFormat: .pcmFormatFloat32, interleaved: false)

            let sampleRate = SCContext.getSampleRate() ?? 48000
            let settings = SCContext.updateAudioSettings(rate: sampleRate)
            SCContext.vW = try? AVAssetWriter.init(outputURL: SCContext.filePath2.url, fileType: fileType)
            SCContext.micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings)
            SCContext.micInput.expectsMediaDataInRealTime = true
            if SCContext.vW.canAdd(SCContext.micInput) { SCContext.vW.add(SCContext.micInput) }
            SCContext.vW.startWriting()
            //SCContext.audioFile2 = try! AVAudioFile(forWriting: SCContext.filePath2.url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } else {
            SCContext.filePath = "\(path).\(fileEnding)"
            SCContext.filePath1 = SCContext.filePath
            SCContext.audioFile = try! AVAudioFile(forWriting: SCContext.filePath.url, settings: SCContext.updateAudioSettings(), commonFormat: .pcmFormatFloat32, interleaved: false)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
    var isMainScreen: Bool {
        guard let id = self.displayID else { return false }
        return (CGDisplayIsMain(id) == 1)
    }
}

extension SCDisplay {
    var nsScreen: NSScreen? {
        return NSScreen.screens.first(where: { $0.displayID == self.displayID })
    }
}

extension AppDelegate {
    func initVideo(conf: SCStreamConfiguration) {
        SCContext.startTime = nil
        
        // Check if recording to file is enabled
        let enableRecording = ud.bool(forKey: "enableRecording")

        // Only create AVAssetWriter infrastructure when recording is enabled
        if enableRecording {
            let fileEnding = videoFormat.rawValue
            var fileType: AVFileType?
            switch fileEnding {
                case VideoFormat.mov.rawValue: fileType = AVFileType.mov
                case VideoFormat.mp4.rawValue: fileType = AVFileType.mp4
                default: assertionFailure("loaded unknown video format".local)
            }

            if remuxAudio && recordMic && recordWinSound {
                SCContext.filePath = "\(SCContext.getFilePath()).\(fileEnding).\(fileEnding).\(fileEnding)"
            } else {
                SCContext.filePath = "\(SCContext.getFilePath()).\(fileEnding)"
            }
            SCContext.vW = try? AVAssetWriter.init(outputURL: SCContext.filePath.url, fileType: fileType!)
            
            let encoderIsH265 = (encoder.rawValue == Encoder.h265.rawValue) || recordHDR
            let fpsMultiplier: Double = Double(frameRate)/8
            let encoderMultiplier: Double = encoderIsH265 ? 0.5 : 0.9
            let resolution = Double(max(600, conf.width)) * Double(max(600, conf.height))
            var qualityMultiplier = 1 - (log10(sqrt(resolution) * fpsMultiplier) / 5)
            switch videoQuality {
                case 0.3: qualityMultiplier = max(0.1, qualityMultiplier)
                case 0.7: qualityMultiplier = max(0.4, min(0.6, qualityMultiplier * 3))
                default: qualityMultiplier = 1.0
            }
            let h264Level = AVVideoProfileLevelH264HighAutoLevel
            let h265Level = recordHDR ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel

            let targetBitrate = resolution * fpsMultiplier * encoderMultiplier * qualityMultiplier * (recordHDR ? 2 : 1)
            print("framerate set in app: \(frameRate)")
            print("target bitrate: \(targetBitrate/1000000)")

            var videoSettings: [String: Any] = [
                AVVideoCodecKey: encoderIsH265 ? ((withAlpha && !recordHDR) ? AVVideoCodecType.hevcWithAlpha : AVVideoCodecType.hevc) : AVVideoCodecType.h264,
                AVVideoWidthKey: conf.width,
                AVVideoHeightKey: conf.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoProfileLevelKey: encoderIsH265 ? h265Level : h264Level,
                    AVVideoAverageBitRateKey: max(200000, Int(targetBitrate)),
                    AVVideoExpectedSourceFrameRateKey: frameRate,
                ] as [String : Any]
            ]
            
            if !recordHDR {
                videoSettings[AVVideoColorPropertiesKey] = [
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2] as [String : Any]
            }
            
            SCContext.vwInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
            SCContext.vwInput.expectsMediaDataInRealTime = true
            
            if SCContext.vW!.canAdd(SCContext.vwInput) { SCContext.vW!.add(SCContext.vwInput) }

            if #available(macOS 13, *) {
                SCContext.awInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: SCContext.updateAudioSettings())
                SCContext.awInput.expectsMediaDataInRealTime = true
                if SCContext.vW!.canAdd(SCContext.awInput) { SCContext.vW!.add(SCContext.awInput) }
            }

            if recordMic {
                let sampleRate = SCContext.getSampleRate() ?? 48000
                let settings = SCContext.updateAudioSettings(rate: sampleRate)
                
                SCContext.micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings)
                SCContext.micInput.expectsMediaDataInRealTime = true
                if SCContext.vW!.canAdd(SCContext.micInput) { 
                    SCContext.vW!.add(SCContext.micInput) 
                    print("Microphone input added to AVAssetWriter for recording")
                } else {
                    print("ERROR: Failed to add microphone input to AVAssetWriter")
                }
            }
            SCContext.vW!.startWriting()
        } else {
            print("Streaming-only mode: No file writer created")
        }
    }
    
    func startMicRecording() {
        if enableAEC {
            var level = AUVoiceIOOtherAudioDuckingLevel.mid
            switch AECLevel {
                case "min": level = .min
                case "max": level = .max
                default: level = .mid
            }
            try? SCContext.AECEngine.startAudioStream(enableAEC: enableAEC, duckingLevel: level, audioBufferHandler: { pcmBuffer in
                if SCContext.isPaused || SCContext.startTime == nil { return }
                
                // Always send microphone audio to mixer for streaming on track 0 (mixed with system audio)
                if let sampleBuffer = pcmBuffer.asSampleBuffer {
                    Task { 
                        await SCContext.mixer?.append(sampleBuffer, track: 0) 
                        if SCContext.mixer != nil {
                            //print("📣 [MIC-AEC] Microphone audio sent to mixer track 0 - format: \(pcmBuffer.format), frames: \(pcmBuffer.frameLength)")
                        }
                    }
                }
                
                // Always write to file if recording is enabled and we have the necessary components
                if ud.bool(forKey: "enableRecording") && SCContext.micInput != nil && SCContext.micInput.isReadyForMoreMediaData {
                    var sampleBufferToWrite = pcmBuffer.asSampleBuffer!
                    // Apply timing adjustment if needed (same as video samples)
                    if SCContext.timeOffset.value > 0 {
                        sampleBufferToWrite = SCContext.adjustTime(sample: sampleBufferToWrite, by: SCContext.timeOffset) ?? sampleBufferToWrite
                    }
                    SCContext.micInput.append(sampleBufferToWrite)
                    //print("Microphone sample written to file (AEC mode)")
                }
            })
            SCContext.aecEngineStarted = true
        } else {
            let input = SCContext.audioEngine.inputNode
            let inputFormat = input.inputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
                if SCContext.isPaused || SCContext.startTime == nil { return }
                
                // Always send microphone audio to mixer for streaming on track 0 (mixed with system audio)
                if let sampleBuffer = buffer.asSampleBuffer {
                   // print("📣 [MIC] Sending mic audio to mixer track 0 - format: \(buffer.format), frames: \(buffer.frameLength)")
                    Task { await SCContext.mixer?.append(sampleBuffer, track: 0) }
                    
                }
                
                // Always write to file if recording is enabled and we have the necessary components
                if ud.bool(forKey: "enableRecording") && SCContext.micInput != nil && SCContext.micInput.isReadyForMoreMediaData {
                    var sampleBufferToWrite = buffer.asSampleBuffer!
                    // Apply timing adjustment if needed (same as video samples)
                    if SCContext.timeOffset.value > 0 {
                        sampleBufferToWrite = SCContext.adjustTime(sample: sampleBufferToWrite, by: SCContext.timeOffset) ?? sampleBufferToWrite
                    }
                    SCContext.micInput.append(sampleBufferToWrite)
                    //print("Microphone sample written to file (AudioEngine mode)")
                }
            }
            try! SCContext.audioEngine.start()
        
        } 
        //    AudioRecorder.shared.setupAudioCapture()
        //    AudioRecorder.shared.start()
        
    }
    
    func outputVideoEffectDidStart(for stream: SCStream) {
        DispatchQueue.main.async { camWindow.close() }
        print("[Presenter Overlay ON]")
        isPresenterON = true
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(poSafeDelay)) {
            self.isCameraReady = true
        }
    }
    
    func outputVideoEffectDidStop(for stream: SCStream) {
        print("[Presenter Overlay OFF]")
        presenterType = "OFF"
        isPresenterON = false
        isCameraReady = false
        DispatchQueue.main.async {
            if SCContext.stream != nil { camWindow.orderFront(self) }
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        if SCContext.saveFrame, let imageBuffer = sampleBuffer.imageBuffer {
            SCContext.saveFrame = false
            
            var ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let url = "\(SCContext.getFilePath(capture: true)).png".url
            if !recordHDR {
                sampleBuffer.nsImage?.saveToFile(url)
            } else {
                let context = CIContext()
                
                // Create the HEIF destination with the correct UTI
                //            if let destination = url? {
                // Specify format and color space (assuming default settings here)
                //                let format = CIFormat.rgb10
                let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
                
                // let colorSpace = ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
                
                // Image exposure needs to be increased by one stop to match the original
                ciImage = ciImage.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 1.0])
                
                //                context.writeHEIF10Representation(of: ciImage, to: destination as! URL, colorSpace: colorSpace)
                do{
                    // try context.writeHEIF10Representation(of:ciImage,
                    //                                       to:url,
                    //                                       colorSpace:colorSpace,
                    //                                       options: [
                    //     kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0
                    if #available(macOS 14.0, *) {
                        try context.writePNGRepresentation(of:ciImage,
                                                           to:url,
                                                           format: .RGB10,
                                                           colorSpace:colorSpace
                        )
                    } else {
                        // Fallback on earlier versions
                        print("RGB10 PNG not supported on this macOS version")
                        try context.writePNGRepresentation(of:ciImage,
                                                           to:url,
                                                           format: .RGBA8,
                                                           colorSpace:colorSpace)
                    }
                    //        try context.writePNGRepresentation(of:outImage, to:outURL, format: .RGBA16,colorSpace:colorSpace,options:[:])
                } catch let error {
                    // Handle the error case
                    print("Error: \(error)")
                }
                //                CGImageDestinationFinalize(destination)
            }
        }
        if SCContext.isPaused { return }
        guard sampleBuffer.isValid else { return }
        var SampleBuffer = sampleBuffer
        if SCContext.isResume {
            SCContext.isResume = false
            var pts = CMSampleBufferGetPresentationTimeStamp(SampleBuffer)
            guard let last = SCContext.lastPTS else { return }
            if last.flags.contains(CMTimeFlags.valid) {
                if SCContext.timeOffset.flags.contains(CMTimeFlags.valid) { pts = CMTimeSubtract(pts, SCContext.timeOffset) }
                let off = CMTimeSubtract(pts, last)
                print("adding \(CMTimeGetSeconds(off)) to \(CMTimeGetSeconds(SCContext.timeOffset)) (pts \(CMTimeGetSeconds(SCContext.timeOffset)))")
                if SCContext.timeOffset.value == 0 { SCContext.timeOffset = off } else { SCContext.timeOffset = CMTimeAdd(SCContext.timeOffset, off) }
            }
            SCContext.lastPTS?.flags = []
        }
        switch outputType {
        case .screen:
            
            // Send video to mixer for streaming on track 0
            Task { await SCContext.mixer?.append(SampleBuffer, track: 0) }
            
            if (SCContext.screen == nil && SCContext.window == nil && SCContext.application == nil) || SCContext.streamType == .systemaudio { break }
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(SampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first else { return }
            guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRawValue),
                  status == .complete else { return }
            
            if SCContext.startTime == nil {
                SCContext.startTime = Date.now
                
                // Start microphone recording BEFORE starting the session so timing is synchronized
                if recordMic && !SCContext.micRecordingStarted {
                    SCContext.micRecordingStarted = true
                    startMicRecording()
                }
                
                // Only start the AVAssetWriter session if recording is enabled and we have a writer
                if ud.bool(forKey: "enableRecording") && SCContext.vW != nil {
                    SCContext.vW!.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(SampleBuffer))
                }
            }
            if (SCContext.timeOffset.value > 0) { SampleBuffer = SCContext.adjustTime(sample: SampleBuffer, by: SCContext.timeOffset) ?? sampleBuffer }
            var pts = CMSampleBufferGetPresentationTimeStamp(SampleBuffer)
            let dur = CMSampleBufferGetDuration(SampleBuffer)
            if (dur.value > 0) { pts = CMTimeAdd(pts, dur) }
            if frameQueue.getArray().contains(where: { $0 >= pts }) { print("Skip this frame"); return } else { frameQueue.append(pts) }
            SCContext.lastPTS = pts
            
            // Handle presenter overlay logic (independent of recording)
            if #available(macOS 14.2, *) {
                if let rect = attachments[.presenterOverlayContentRect] as? [String: Any]{
                    var type = "np"
                    let off = (rect["X"] as! CGFloat == .infinity)
                    let small = (rect["X"] as! CGFloat == 0.0)
                    let big = (!off && !small)
                    if off { type = "OFF" } else if small { type = "Small" } else if big { type = "Big" }
                    if type != presenterType {
                        print("Presenter Overlay set to \"\(type)\"!")
                        isCameraReady = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(poSafeDelay)) {
                            self.isCameraReady = true
                        }
                        presenterType = type
                    }
                }
            }
            if isPresenterON && !isCameraReady { break }
            if SCContext.firstFrame == nil { SCContext.firstFrame = SampleBuffer }
            
            // Only write to file if recording is enabled and we have the necessary components
            if ud.bool(forKey: "enableRecording") && SCContext.vwInput != nil && SCContext.vwInput.isReadyForMoreMediaData {
                SCContext.vwInput.append(SampleBuffer)
            }
            break
        case .audio:
            
            // Send system audio to mixer for streaming on track 0
            Task { 
                await SCContext.mixer?.append(SampleBuffer, track: 1) 
                if SCContext.mixer != nil {
                    let audioFormat = CMSampleBufferGetFormatDescription(SampleBuffer)
                    let sampleCount = CMSampleBufferGetNumSamples(SampleBuffer)
                    //print("🔊 [SYS] System audio sent to mixer track 0 - samples: \(sampleCount), format: \(audioFormat?.audioFormatList.first.debugDescription ?? "unknown")")
                }
            }
            
            if SCContext.streamType == .systemaudio { // write directly to file if not video recording
                hideMousePointer = true
                if SCContext.startTime == nil {
                    // Start microphone recording BEFORE starting the session so timing is synchronized
                    if recordMic && !SCContext.micRecordingStarted {
                        SCContext.micRecordingStarted = true
                        startMicRecording()
                    }
                    
                    // Only start the AVAssetWriter session if recording is enabled and we have a writer
                    if ud.bool(forKey: "enableRecording") && SCContext.vW != nil {
                        SCContext.vW!.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(SampleBuffer))
                    }
                }
                if SCContext.startTime == nil { SCContext.startTime = Date.now }
                
                // Only write audio to file if recording is enabled
                if ud.bool(forKey: "enableRecording") {
                    guard let samples = SampleBuffer.asPCMBuffer else { return }
                    do { try SCContext.audioFile?.write(from: samples) }
                    catch { assertionFailure("audio file writing issue".local) }
                }
                
            } else {
                if SCContext.lastPTS == nil { return }
                // Only write audio to file if recording is enabled and we have the necessary components
                if ud.bool(forKey: "enableRecording") && SCContext.awInput != nil && SCContext.awInput.isReadyForMoreMediaData {
                    SCContext.awInput.append(SampleBuffer)
                }
            }
#if compiler(>=6.0)
        case .microphone:
            break
#endif
        @unknown default:
            assertionFailure("unknown stream type".local)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { // stream error
        print("closing stream with error:\n".local, error,
              "\nthis might be due to the window closing or the user stopping from the sonoma ui".local)
        DispatchQueue.main.async {
            SCContext.stream = nil
            SCContext.stopRecording()
        }
    }
}

class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let shared = AudioRecorder()
    private var captureSession: AVCaptureSession!
    private var audioInput: AVCaptureDeviceInput!
    private var audioDataOutput: AVCaptureAudioDataOutput!

    func setupAudioCapture() {
        captureSession = AVCaptureSession()

        // Get the default audio device (microphone)
        guard let audioDevice = SCContext.getCurrentMic() else {
            print("Unable to access microphone")
            return
        }
        
        // Create audio input
        do {
            audioInput = try AVCaptureDeviceInput(device: audioDevice)
        } catch {
            print("Unable to create audio input: \(error)")
            return
        }
        
        // Add audio input to capture session
        if captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        } else {
            print("Unable to add audio input to capture session")
            return
        }

        // Create audio data output
        audioDataOutput = AVCaptureAudioDataOutput()
        let audioQueue = DispatchQueue(label: "audioQueue")
        audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)
        
        // Add audio data output to capture session
        if captureSession.canAddOutput(audioDataOutput) {
            captureSession.addOutput(audioDataOutput)
        } else {
            print("Unable to add audio data output to capture session")
            return
        }
    }
    
    func start() {
        if let session = captureSession {
            session.startRunning()
        }
    }
    
    func stop() {
        if let session = captureSession {
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if SCContext.isPaused || SCContext.startTime == nil { return }
        
        // Always send microphone audio to mixer for streaming on track 0 (mixed with system audio)
        Task { 
            await SCContext.mixer?.append(sampleBuffer, track: 0) 
            if SCContext.mixer != nil {
                let audioFormat = CMSampleBufferGetFormatDescription(sampleBuffer)
                let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
                //print("📣 [MIC-AV] Microphone audio sent to mixer track 0 - samples: \(sampleCount), format: \(audioFormat?.audioFormatList.first.debugDescription ?? "unknown")")
            }
        }
        
        // Always write to file if recording is enabled and we have the necessary components
        if ud.bool(forKey: "enableRecording") && SCContext.micInput != nil && SCContext.micInput.isReadyForMoreMediaData {
            var sampleBufferToWrite = sampleBuffer
            // Apply timing adjustment if needed (same as video samples)
            if SCContext.timeOffset.value > 0 {
                sampleBufferToWrite = SCContext.adjustTime(sample: sampleBufferToWrite, by: SCContext.timeOffset) ?? sampleBufferToWrite
            }
            SCContext.micInput.append(sampleBufferToWrite)
            //print("Microphone sample written to file (AVCapture mode)")
        }
    }
}

// https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos
// For Sonoma updated to https://developer.apple.com/forums/thread/727709
extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        try? self.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            guard let absd = self.formatDescription?.audioStreamBasicDescription else { return nil }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
        }
    }
    
    var nsImage: NSImage? {
        return autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let ciContext = CIContext()
            if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
            return nil
        }
    }
}

// Based on https://gist.github.com/aibo-cora/c57d1a4125e145e586ecb61ebecff47c
extension AVAudioPCMBuffer {
    var asSampleBuffer: CMSampleBuffer? {
        let asbd = self.format.streamDescription
        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil

        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(self.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: self.mutableAudioBufferList
        ) == noErr else { return nil }

        return sampleBuffer
    }
}
